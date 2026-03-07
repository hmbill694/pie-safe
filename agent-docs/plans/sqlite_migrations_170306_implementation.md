# SQLite Migration Runner — Implementation Plan

## Overview

- **`simplifile` and `gleam_crypto`** are added as explicit dependencies to `gleam.toml`. Both are already transitively resolved in the manifest (via `parrot` and `gramps` respectively), so no `gleam deps download` is required — only the TOML edit.
- **`simplifile`** replaces all Erlang `:file` FFI: `simplifile.read_directory/1` handles directory listing (returns `List(String)` of plain filenames, no charlist conversion needed) and `simplifile.read/1` handles file reading. **No `@external` FFI is needed in `migrations.gleam` at all.**
- **`gleam/crypto`** (`gleam_crypto` package) provides `crypto.hash(crypto.Sha256, data: BitArray) -> BitArray`; hex encoding uses `bit_array.base16_encode/1` from stdlib.
- **`_migrations` table** has columns: `version INTEGER PRIMARY KEY`, `sha256 TEXT NOT NULL`, `applied_at TEXT NOT NULL`.
- **Hash validation** runs at startup for every already-applied migration found on disk: if the stored hash and the computed hash of the file diverge, `run/2` returns an error immediately before applying any new migrations.
- **Transaction approach**: `sqlight.exec` for `BEGIN` / `COMMIT` / `ROLLBACK`, `sqlight.exec` for migration SQL body, `sqlight.query` for the parameterised `INSERT INTO _migrations`.

---

## Checklist

### 1. Dependency Check & `gleam.toml` Update

- [ ] **1.1** Open `backend/gleam.toml`. In the `[dependencies]` block, add:
  ```toml
  simplifile    = ">= 2.3.2 and < 3.0.0"
  gleam_crypto  = ">= 1.5.1 and < 2.0.0"
  ```
  Both are already transitively resolved in `manifest.toml` (`simplifile` via `parrot`, `gleam_crypto` via `gramps`/`parrot`). No `gleam deps download` needed.

---

### 2. Create `priv/migrations` Directory Structure

- [ ] **2.1** Create `backend/priv/migrations/registry/`
- [ ] **2.2** Create `backend/priv/migrations/family/`

---

### 3. Write Migration SQL Files

- [ ] **3.1** Create `backend/priv/migrations/registry/001_initial_schema.sql` — verbatim copy of the `registry_ddl` const from `registry_actor.gleam` (the `PRAGMA foreign_keys = ON` line plus the three `CREATE TABLE IF NOT EXISTS` statements for `families`, `accounts`, `registry_auth_tokens`)

- [ ] **3.2** Create `backend/priv/migrations/family/001_initial_schema.sql` — verbatim copy of the `family_ddl` const from `family_db_actor.gleam` (the `PRAGMA foreign_keys = ON` line plus all 14 `CREATE TABLE IF NOT EXISTS` statements)

---

### 4. Implement `backend/src/backend/migrations.gleam`

- [ ] **4.1** Write the module header with all imports — no `@external` FFI declarations:
  ```gleam
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
  ```

- [ ] **4.2** Define private type:
  ```gleam
  type Migration {
    Migration(version: Int, filename: String, sql: String, sha256: String)
  }
  ```
  The `sha256` field holds the lowercase hex-encoded SHA-256 of `sql`, computed once at load time.

- [ ] **4.3** `compute_hash(sql: String) -> String`
  1. `bit_array.from_string(sql)` → `BitArray`
  2. `crypto.hash(crypto.Sha256, content)` → `BitArray`
  3. `bit_array.base16_encode(hash_bits)` → uppercase hex `String`
  4. `string.lowercase(...)` → lowercase hex `String`

- [ ] **4.4** `parse_version(filename: String) -> Result(Int, Nil)`
  1. If filename does not end with `.sql` → `Error(Nil)`
  2. If `string.length(filename) < 3` → `Error(Nil)`
  3. Slice first 3 chars: `string.slice(filename, 0, 3)`
  4. `int.parse(prefix)` → `Ok(version)` or `Error(Nil)`

- [ ] **4.5** `load_migrations(dir: String) -> Result(List(Migration), String)`
  1. `simplifile.read_directory(at: dir)` → map error to descriptive `String`
  2. For each filename: `parse_version` — skip with `io.println` log on `Error(Nil)`
  3. For each valid version: `simplifile.read(from: dir <> "/" <> filename)` → map error to descriptive `String`
  4. Compute `compute_hash(sql)` immediately after reading
  5. Build `Migration(version:, filename:, sql:, sha256:)` records
  6. Sort ascending by `version`
  7. Return `Ok(sorted_migrations)`

- [ ] **4.6** `bootstrap_migrations_table(conn: sqlight.Connection) -> Result(Nil, String)`
  ```sql
  CREATE TABLE IF NOT EXISTS _migrations (
    version    INTEGER PRIMARY KEY,
    sha256     TEXT NOT NULL,
    applied_at TEXT NOT NULL
  );
  ```
  via `sqlight.exec(sql, on: conn)`.

- [ ] **4.7** `get_current_version(conn: sqlight.Connection) -> Result(Int, String)`
  - `SELECT COALESCE(MAX(version), 0) FROM _migrations`
  - Decoder: `decode.element(0, decode.int)`
  - Pattern match result list: `[v] -> Ok(v)`

- [ ] **4.8** `get_stored_hash(conn: sqlight.Connection, version: Int) -> Result(String, String)`
  - `SELECT sha256 FROM _migrations WHERE version = ?` with `[sqlight.int(version)]`
  - Decoder: `decode.element(0, decode.string)`
  - Pattern match: `[hash] -> Ok(hash)`, `[] -> Error("No _migrations row found for version " <> int.to_string(version))`

- [ ] **4.9** `validate_applied_migration(conn: sqlight.Connection, migration: Migration) -> Result(Nil, String)`
  1. Call `get_stored_hash(conn, migration.version)`
  2. Compare `stored_hash` to `migration.sha256`
  3. Match → `Ok(Nil)`
  4. Mismatch → `Error("Migration " <> int.to_string(migration.version) <> " (" <> migration.filename <> ") has been modified after being applied. Expected hash " <> stored_hash <> ", got " <> migration.sha256 <> ".")`

- [ ] **4.10** `apply_migration(conn: sqlight.Connection, migration: Migration, now: String) -> Result(Nil, String)`
  1. `sqlight.exec("BEGIN;", on: conn)` — error → return `Error`
  2. `sqlight.exec(migration.sql, on: conn)` — error → `ROLLBACK` then `Error`
  3. `sqlight.query("INSERT INTO _migrations (version, sha256, applied_at) VALUES (?, ?, ?)", on: conn, with: [sqlight.int(migration.version), sqlight.text(migration.sha256), sqlight.text(now)], expecting: decode.success(Nil))` — error → `ROLLBACK` then `Error`
  4. `sqlight.exec("COMMIT;", on: conn)` — error → `ROLLBACK` then `Error`
  5. Return `Ok(Nil)`

- [ ] **4.11** `pub fn run(conn: sqlight.Connection, migrations_dir: String) -> Result(Nil, String)`
  1. `use _ <- result.try(bootstrap_migrations_table(conn))`
  2. `use migrations <- result.try(load_migrations(migrations_dir))`
  3. `use current_version <- result.try(get_current_version(conn))`
  4. Partition:
     ```gleam
     let applied   = list.filter(migrations, fn(m) { m.version <= current_version })
     let unapplied = list.filter(migrations, fn(m) { m.version > current_version })
     ```
  5. Validate applied: `list.try_each(applied, validate_applied_migration(conn, _))` — return first error
  6. Compute now: `timestamp.system_time() |> timestamp.to_rfc3339(calendar.utc_offset)`
  7. Apply unapplied: `list.try_each(unapplied, apply_migration(conn, _, now))` — stop on first error
  8. Return `Ok(Nil)`

---

### 5. Update `registry_actor.gleam`

- [ ] **5.1** Add `import backend/migrations`
- [ ] **5.2** Delete `const registry_ddl = "..."` (lines 11–40)
- [ ] **5.3** Delete `fn run_ddl(conn)` (lines 106–109)
- [ ] **5.4** Replace `use _ <- result.try(run_ddl(conn))` with `use _ <- result.try(migrations.run(conn, "priv/migrations/registry"))`

---

### 6. Update `family_db_actor.gleam`

- [ ] **6.1** Add `import backend/migrations`
- [ ] **6.2** Delete `const family_ddl = "..."` (lines 9–178)
- [ ] **6.3** Delete `fn run_family_ddl(conn)` (lines 235–238)
- [ ] **6.4** Replace `use _ <- result.try(run_family_ddl(conn))` with `use _ <- result.try(migrations.run(conn, "priv/migrations/family"))`

---

### 7. Verification Steps

- [ ] **7.1** `gleam build` from `backend/` — zero compile errors
- [ ] **7.2** Fresh registry DB smoke test — confirm `_migrations` table present with `version=1`, 64-char sha256, and `applied_at` timestamp
- [ ] **7.3** Fresh family DB smoke test — all 14 tables + `_migrations` with `version=1`
- [ ] **7.4** Idempotency test — restart against existing DBs, startup succeeds, no migrations re-applied
- [ ] **7.5** Hash mismatch test — edit a migration file, restart, confirm hard error: `"Migration 1 (001_initial_schema.sql) has been modified after being applied. Expected hash <X>, got <Y>."`
- [ ] **7.6** Invalid filename test — drop a non-`.sql` file in a migrations dir, confirm log warning and normal startup

---

## Key Design Reference

| Topic | Decision |
|---|---|
| Directory listing | `simplifile.read_directory(at: dir)` → `Result(List(String), FileError)` |
| File reading | `simplifile.read(from: path)` → `Result(String, FileError)` |
| No FFI | All I/O via `simplifile`; no `@external` declarations in `migrations.gleam` |
| Hash algorithm | SHA-256 via `crypto.hash(crypto.Sha256, bit_array.from_string(sql))` |
| Hash encoding | `bit_array.base16_encode` → `string.lowercase` → 64-char lowercase hex |
| Hash timing | Computed once at load time, stored on `Migration` record |
| Validation order | All already-applied validated **before** any new migration is applied |
| UTC timestamp | `timestamp.system_time() \|> timestamp.to_rfc3339(calendar.utc_offset)` |
| Transaction scope | Per-migration; `ROLLBACK` on any step failure |
| Iteration | `list.try_each` for both validation and apply loops |
| Mismatch behaviour | Hard error — `run/2` returns `Error(String)`, actor init fails |
