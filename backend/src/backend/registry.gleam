import gleam/io
import sqlight

const registry_ddl = "
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

pub fn init(db_path: String) -> Nil {
  io.println("Initializing registry DB at: " <> db_path)
  let assert Ok(conn) = sqlight.open(db_path)
  let assert Ok(_) = sqlight.exec("PRAGMA foreign_keys = ON;", on: conn)
  let assert Ok(_) = sqlight.exec(registry_ddl, on: conn)
  let assert Ok(_) = sqlight.close(conn)
  io.println("Registry DB initialized.")
}
