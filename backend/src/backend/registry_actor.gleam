import backend/db
import backend/migrations
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/option.{type Option}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import registry/sql as registry_sql
import sqlight

pub type Message {
  GetFamily(
    reply_to: Subject(Result(Option(registry_sql.GetFamily), String)),
    id: String,
  )
  GetDbPathForFamily(
    reply_to: Subject(Result(String, String)),
    family_id: String,
  )
  GetAccountByEmail(
    reply_to: Subject(Result(Option(registry_sql.GetAccountByEmail), String)),
    email: String,
  )
  InsertFamily(
    reply_to: Subject(Result(Nil, String)),
    id: String,
    name: String,
    db_path: String,
    status: String,
    created_at: String,
  )
  InsertAccount(
    reply_to: Subject(Result(Nil, String)),
    family_id: String,
    email: String,
    role: String,
    created_at: String,
    last_login_at: Option(String),
  )
  GetAccount(
    reply_to: Subject(Result(Option(registry_sql.GetAccount), String)),
    id: Int,
  )
  InsertRegistryAuthToken(
    reply_to: Subject(Result(Nil, String)),
    account_id: Int,
    token_hash: String,
    token_type: String,
    expires_at: String,
    used_at: Option(String),
    created_at: String,
  )
  GetRegistryAuthTokenByHash(
    reply_to: Subject(
      Result(Option(registry_sql.GetRegistryAuthTokenByHash), String),
    ),
    token_hash: String,
  )
  MarkRegistryAuthTokenUsed(
    reply_to: Subject(Result(Nil, String)),
    used_at: String,
    id: Int,
  )
  UpdateAccountLastLogin(
    reply_to: Subject(Result(Nil, String)),
    last_login_at: String,
    id: Int,
  )
}

type State {
  State(conn: sqlight.Connection)
}

pub fn supervised(
  db_path: String,
  name: process.Name(Message),
  migrations_dir: String,
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start(db_path, name, migrations_dir) })
}

pub fn start(
  db_path: String,
  name: process.Name(Message),
  migrations_dir: String,
) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(5000, fn(subject) {
    use conn <- result.try(open_db(db_path))
    use _ <- result.try(migrations.run(conn, migrations_dir))
    actor.initialised(State(conn:))
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.named(name)
  |> actor.start
}

fn open_db(db_path: String) -> Result(sqlight.Connection, String) {
  io.println("Opening registry DB at: " <> db_path)
  sqlight.open(db_path)
  |> result.map_error(fn(err) { "Failed to open registry DB: " <> err.message })
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    GetFamily(reply_to:, id:) -> {
      let result =
        db.exec_query(state.conn, registry_sql.get_family(id))
        |> result.map(fn(rows) {
          case rows {
            [row, ..] -> option.Some(row)
            [] -> option.None
          }
        })
      process.send(reply_to, result)
      actor.continue(state)
    }

    GetDbPathForFamily(reply_to:, family_id:) -> {
      let result =
        db.exec_query(state.conn, registry_sql.get_family(family_id))
        |> result.try(fn(rows) {
          case rows {
            [row, ..] -> Ok(row.db_path)
            [] -> Error("No family found with id: " <> family_id)
          }
        })
      process.send(reply_to, result)
      actor.continue(state)
    }

    GetAccountByEmail(reply_to:, email:) -> {
      let result =
        db.exec_query(state.conn, registry_sql.get_account_by_email(email))
        |> result.map(fn(rows) {
          case rows {
            [row, ..] -> option.Some(row)
            [] -> option.None
          }
        })
      process.send(reply_to, result)
      actor.continue(state)
    }

    InsertFamily(reply_to:, id:, name:, db_path:, status:, created_at:) -> {
      let result =
        db.exec_command(
          state.conn,
          registry_sql.insert_family(id, name, db_path, status, created_at),
        )
      process.send(reply_to, result)
      actor.continue(state)
    }

    InsertAccount(
      reply_to:,
      family_id:,
      email:,
      role:,
      created_at:,
      last_login_at:,
    ) -> {
      let result =
        db.exec_command(
          state.conn,
          registry_sql.insert_account(
            family_id,
            email,
            role,
            created_at,
            last_login_at,
          ),
        )
      process.send(reply_to, result)
      actor.continue(state)
    }

    GetAccount(reply_to:, id:) -> {
      let result =
        db.exec_query(state.conn, registry_sql.get_account(id))
        |> result.map(fn(rows) {
          case rows {
            [row, ..] -> option.Some(row)
            [] -> option.None
          }
        })
      process.send(reply_to, result)
      actor.continue(state)
    }

    InsertRegistryAuthToken(
      reply_to:,
      account_id:,
      token_hash:,
      token_type:,
      expires_at:,
      used_at:,
      created_at:,
    ) -> {
      let result =
        db.exec_command(
          state.conn,
          registry_sql.insert_registry_auth_token(
            account_id,
            token_hash,
            token_type,
            expires_at,
            used_at,
            created_at,
          ),
        )
      process.send(reply_to, result)
      actor.continue(state)
    }

    GetRegistryAuthTokenByHash(reply_to:, token_hash:) -> {
      let result =
        db.exec_query(
          state.conn,
          registry_sql.get_registry_auth_token_by_hash(token_hash),
        )
        |> result.map(fn(rows) {
          case rows {
            [row, ..] -> option.Some(row)
            [] -> option.None
          }
        })
      process.send(reply_to, result)
      actor.continue(state)
    }

    MarkRegistryAuthTokenUsed(reply_to:, used_at:, id:) -> {
      let result =
        db.exec_command(
          state.conn,
          registry_sql.mark_registry_auth_token_used(used_at, id),
        )
      process.send(reply_to, result)
      actor.continue(state)
    }

    UpdateAccountLastLogin(reply_to:, last_login_at:, id:) -> {
      let result =
        db.exec_command(
          state.conn,
          registry_sql.update_account_last_login(last_login_at, id),
        )
      process.send(reply_to, result)
      actor.continue(state)
    }
  }
}
