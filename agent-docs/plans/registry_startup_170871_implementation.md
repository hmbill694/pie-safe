# Implementation Plan: Registry DB Startup Initialization

## Overview

Four discrete changes are needed:
1. Add `envoy` as a direct dep in `gleam.toml`
2. Create `backend/src/backend/config.gleam`
3. Create `backend/src/backend/registry.gleam`
4. Update `backend/src/backend.gleam`

---

## Checklist

- [ ] **Step 1 — Add `envoy` to `backend/gleam.toml` direct dependencies**

  In the `[dependencies]` section, add one line:

  ```toml
  envoy = ">= 1.1.0 and < 2.0.0"
  ```

---

- [ ] **Step 2 — Create `backend/src/backend/config.gleam`**

  ```gleam
  import envoy
  import gleam/int

  pub type Config {
    Config(registry_db_path: String, port: Int)
  }

  pub fn load() -> Config {
    let registry_db_path = case envoy.get("REGISTRY_DB_PATH") {
      Ok(v) -> v
      Error(Nil) ->
        panic as "Missing required environment variable: REGISTRY_DB_PATH"
    }

    let port_str = case envoy.get("PORT") {
      Ok(v) -> v
      Error(Nil) ->
        panic as "Missing required environment variable: PORT"
    }

    let port = case int.parse(port_str) {
      Ok(p) -> p
      Error(Nil) ->
        panic as "Invalid value for PORT: must be a valid integer"
    }

    Config(registry_db_path: registry_db_path, port: port)
  }
  ```

---

- [ ] **Step 3 — Create `backend/src/backend/registry.gleam`**

  ```gleam
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
  ```

---

- [ ] **Step 4 — Update `backend/src/backend.gleam`**

  Remove the stale `run_startup_query`, `parrot_to_sqlight`, and the top-level `use conn <- sqlight.with_connection(...)`. Remove unused imports (`sqlight`, `parrot/dev`, `backend/sql`, `gleam/list`). Call `config.load()` and `registry.init()`. Use `config.port` for mist.

  ```gleam
  import backend/config
  import backend/registry
  import gleam/bytes_tree
  import gleam/erlang/process
  import gleam/http/request.{type Request}
  import gleam/http/response.{type Response}
  import gleam/io
  import gleam/option.{None}
  import gleam/result
  import gleam/string
  import mist.{type Connection, type ResponseData}

  const index_html = "<!DOCTYPE html>
  <html lang=\"en\">
    <head>
      <meta charset=\"UTF-8\" />
      <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />
      <title>pie-safe</title>
      <link rel=\"stylesheet\" href=\"/static/ui.css\" />
    </head>
    <body>
      <div id=\"app\"></div>
      <script type=\"module\" src=\"/static/ui.js\"></script>
    </body>
  </html>"

  pub fn main() {
    let config = config.load()
    registry.init(config.registry_db_path)

    let not_found =
      response.new(404)
      |> response.set_body(mist.Bytes(bytes_tree.from_string("Not found")))

    let assert Ok(_) =
      fn(req: Request(Connection)) -> Response(ResponseData) {
        case request.path_segments(req) {
          [] ->
            response.new(200)
            |> response.set_header("content-type", "text/html; charset=utf-8")
            |> response.set_body(mist.Bytes(bytes_tree.from_string(index_html)))

          ["static", ..rest] -> serve_static(rest, not_found)

          _ -> not_found
        }
      }
      |> mist.new
      |> mist.port(config.port)
      |> mist.start

    io.println(
      "Server running on http://localhost:" <> string.inspect(config.port),
    )
    process.sleep_forever()
  }

  fn serve_static(
    path_parts: List(String),
    not_found: Response(ResponseData),
  ) -> Response(ResponseData) {
    let file_path = "priv/static/" <> string.join(path_parts, "/")

    mist.send_file(file_path, offset: 0, limit: None)
    |> result.map(fn(file) {
      let content_type = guess_content_type(file_path)
      response.new(200)
      |> response.set_header("content-type", content_type)
      |> response.set_body(file)
    })
    |> result.unwrap(not_found)
  }

  fn guess_content_type(path: String) -> String {
    case string.ends_with(path, ".js") {
      True -> "application/javascript"
      False ->
        case string.ends_with(path, ".css") {
          True -> "text/css"
          False -> "application/octet-stream"
        }
    }
  }
  ```

---

## What is NOT changed
- `backend/src/backend/sql.gleam` — auto-generated by parrot, do not touch
- `backend/manifest.toml` — auto-managed by Gleam tooling, do not touch
- `backend/src/sql/registry_schema.sql` — reference only; DDL is embedded in `registry.gleam`
- No persistent connection added to the request handler; connection is opened, used for DDL, and closed before HTTP server starts
