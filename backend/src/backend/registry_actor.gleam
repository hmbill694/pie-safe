import backend/db
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/option.{type Option}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import registry/sql as registry_sql
import sqlight

const registry_ddl = "
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS families (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  db_path    TEXT NOT NULL UNIQUE,
  status     TEXT NOT NULL DEFAULT 'active',
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS accounts (
  id            INTEGER PRIMARY KEY,
  family_id     TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  email         TEXT NOT NULL UNIQUE,
  role          TEXT NOT NULL DEFAULT 'member',
  created_at    TEXT NOT NULL,
  last_login_at TEXT
);

CREATE TABLE IF NOT EXISTS registry_auth_tokens (
  id         INTEGER PRIMARY KEY,
  account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL,
  token_type TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  used_at    TEXT,
  created_at TEXT NOT NULL
);
"

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
}

type State {
  State(conn: sqlight.Connection)
}

pub fn supervised(
  db_path: String,
  name: process.Name(Message),
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start(db_path, name) })
}

pub fn start(
  db_path: String,
  name: process.Name(Message),
) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(5000, fn(subject) {
    use conn <- result.try(open_db(db_path))
    use _ <- result.try(run_ddl(conn))
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

fn run_ddl(conn: sqlight.Connection) -> Result(Nil, String) {
  sqlight.exec(registry_ddl, on: conn)
  |> result.map_error(fn(err) { "Failed to run registry DDL: " <> err.message })
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
  }
}
