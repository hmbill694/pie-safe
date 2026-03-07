import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import simplifile
import sqlight

type Migration {
  Migration(version: Int, filename: String, sql: String, sha256: String)
}

fn compute_hash(sql: String) -> String {
  let content = bit_array.from_string(sql)
  let hash_bits = crypto.hash(crypto.Sha256, content)
  bit_array.base16_encode(hash_bits)
  |> string.lowercase
}

fn parse_version(filename: String) -> Result(Int, Nil) {
  case string.ends_with(filename, ".sql") {
    False -> Error(Nil)
    True ->
      case string.length(filename) < 3 {
        True -> Error(Nil)
        False -> {
          let prefix = string.slice(filename, 0, 3)
          int.parse(prefix)
        }
      }
  }
}

fn load_migrations(dir: String) -> Result(List(Migration), String) {
  use filenames <- result.try(
    simplifile.read_directory(at: dir)
    |> result.map_error(fn(e) {
      "Failed to list migrations directory "
      <> dir
      <> ": "
      <> simplifile.describe_error(e)
    }),
  )

  let migrations =
    list.filter_map(filenames, fn(filename) {
      case parse_version(filename) {
        Error(Nil) -> {
          io.println(
            "Skipping non-migration file in migrations dir: " <> filename,
          )
          Error(Nil)
        }
        Ok(version) -> {
          let path = dir <> "/" <> filename
          case simplifile.read(from: path) {
            Error(e) -> {
              io.println(
                "Failed to read migration file "
                <> path
                <> ": "
                <> simplifile.describe_error(e),
              )
              Error(Nil)
            }
            Ok(sql) -> {
              let sha256 = compute_hash(sql)
              Ok(Migration(version:, filename:, sql:, sha256:))
            }
          }
        }
      }
    })

  let sorted =
    list.sort(migrations, fn(a, b) { int.compare(a.version, b.version) })

  Ok(sorted)
}

fn bootstrap_migrations_table(conn: sqlight.Connection) -> Result(Nil, String) {
  let sql =
    "CREATE TABLE IF NOT EXISTS _migrations (
  version    INTEGER PRIMARY KEY,
  sha256     TEXT NOT NULL,
  applied_at TEXT NOT NULL
);"
  sqlight.exec(sql, on: conn)
  |> result.map_error(fn(err) {
    "Failed to bootstrap _migrations table: " <> err.message
  })
}

fn get_current_version(conn: sqlight.Connection) -> Result(Int, String) {
  let sql = "SELECT COALESCE(MAX(version), 0) FROM _migrations"
  let decoder = {
    use v <- decode.field(0, decode.int)
    decode.success(v)
  }
  case sqlight.query(sql, on: conn, with: [], expecting: decoder) {
    Error(err) ->
      Error("Failed to get current migration version: " <> err.message)
    Ok([v]) -> Ok(v)
    Ok(_) -> Error("Unexpected result from version query")
  }
}

fn get_stored_hash(
  conn: sqlight.Connection,
  version: Int,
) -> Result(String, String) {
  let sql = "SELECT sha256 FROM _migrations WHERE version = ?"
  let decoder = {
    use hash <- decode.field(0, decode.string)
    decode.success(hash)
  }
  case
    sqlight.query(
      sql,
      on: conn,
      with: [sqlight.int(version)],
      expecting: decoder,
    )
  {
    Error(err) ->
      Error(
        "Failed to get stored hash for version "
        <> int.to_string(version)
        <> ": "
        <> err.message,
      )
    Ok([hash]) -> Ok(hash)
    Ok([]) ->
      Error("No _migrations row found for version " <> int.to_string(version))
    Ok(_) ->
      Error(
        "Unexpected result querying hash for version " <> int.to_string(version),
      )
  }
}

fn validate_applied_migration(
  conn: sqlight.Connection,
  migration: Migration,
) -> Result(Nil, String) {
  use stored_hash <- result.try(get_stored_hash(conn, migration.version))
  case stored_hash == migration.sha256 {
    True -> Ok(Nil)
    False ->
      Error(
        "Migration "
        <> int.to_string(migration.version)
        <> " ("
        <> migration.filename
        <> ") has been modified after being applied. Expected hash "
        <> stored_hash
        <> ", got "
        <> migration.sha256
        <> ".",
      )
  }
}

fn apply_migration(
  conn: sqlight.Connection,
  migration: Migration,
  now: String,
) -> Result(Nil, String) {
  use _ <- result.try(
    sqlight.exec("BEGIN;", on: conn)
    |> result.map_error(fn(err) {
      "Failed to BEGIN transaction for migration "
      <> int.to_string(migration.version)
      <> ": "
      <> err.message
    }),
  )

  let rollback = fn(msg) {
    let _ = sqlight.exec("ROLLBACK;", on: conn)
    Error(msg)
  }

  case sqlight.exec(migration.sql, on: conn) {
    Error(err) ->
      rollback(
        "Failed to apply migration "
        <> int.to_string(migration.version)
        <> " ("
        <> migration.filename
        <> "): "
        <> err.message,
      )
    Ok(_) -> {
      let insert_sql =
        "INSERT INTO _migrations (version, sha256, applied_at) VALUES (?, ?, ?)"
      let args = [
        sqlight.int(migration.version),
        sqlight.text(migration.sha256),
        sqlight.text(now),
      ]
      case
        sqlight.query(
          insert_sql,
          on: conn,
          with: args,
          expecting: decode.success(Nil),
        )
      {
        Error(err) ->
          rollback(
            "Failed to record migration "
            <> int.to_string(migration.version)
            <> ": "
            <> err.message,
          )
        Ok(_) -> {
          case sqlight.exec("COMMIT;", on: conn) {
            Error(err) ->
              rollback(
                "Failed to COMMIT migration "
                <> int.to_string(migration.version)
                <> ": "
                <> err.message,
              )
            Ok(_) -> {
              io.println(
                "Applied migration "
                <> int.to_string(migration.version)
                <> " ("
                <> migration.filename
                <> ")",
              )
              Ok(Nil)
            }
          }
        }
      }
    }
  }
}

pub fn run(
  conn: sqlight.Connection,
  migrations_dir: String,
) -> Result(Nil, String) {
  use _ <- result.try(bootstrap_migrations_table(conn))
  use migrations <- result.try(load_migrations(migrations_dir))
  use current_version <- result.try(get_current_version(conn))

  let applied = list.filter(migrations, fn(m) { m.version <= current_version })
  let unapplied = list.filter(migrations, fn(m) { m.version > current_version })

  use _ <- result.try(
    list.try_each(applied, fn(m) { validate_applied_migration(conn, m) }),
  )

  let now =
    timestamp.system_time()
    |> timestamp.to_rfc3339(calendar.utc_offset)

  list.try_each(unapplied, fn(m) { apply_migration(conn, m, now) })
}
