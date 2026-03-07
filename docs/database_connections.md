# Pie Safe — Database Connection Management

## Overview

Pie Safe manages two categories of SQLite databases:

1. **Registry DB** (`data/registry.db`) — a single, application-wide database that is opened once at startup and held open for the lifetime of the application.
2. **Per-family DBs** (`data/<uuid>.db`) — one database per registered family, opened lazily on first access and evicted from memory after a configurable idle period.

All database connections are managed as **OTP actors** in a supervisor tree, giving the application automatic restart semantics, fault isolation, and named process discovery.

---

## OTP Supervisor Tree

```
main() — backend.gleam
  │
  ├─ config.load()
  │
  └─ static_supervisor (OneForOne restart strategy)
        ├─ RegistryActor        — opens registry.db at startup
        └─ FamilyDbSupervisor   — pool actor for per-family connections

DbEvictor — spawned as a linked process after the supervisor starts
```

### Named Process Discovery

Actor names are created **once** in `main()` using `process.new_name(prefix:)` and passed into supervisor worker closures. Each actor registers itself under its name on start via `actor.named(builder, name)`. Any module that needs to communicate with an actor looks it up with `process.named_subject(name)` rather than holding onto a `Subject` directly. This avoids the need to thread `Subject` values through the call stack.

---

## Registry Actor (`backend/src/backend/registry_actor.gleam`)

The `RegistryActor` manages the single persistent connection to `registry.db`.

### Startup Sequence

On initialisation:

1. Open a SQLite connection to `config.registry_db_path`
2. Enable foreign key enforcement: `PRAGMA foreign_keys = ON`
3. Run the migration runner (`migrations.run(conn, "priv/migrations/registry")`) to apply any unapplied schema migrations
4. Register the actor under its well-known name
5. Begin handling messages

Any failure in these steps causes the actor to return `Error(String)`, which triggers the OTP supervisor to crash the application (since the registry is required for the app to function).

### Message Protocol

The `RegistryActor` exposes a typed message protocol for all registry database operations:

| Message | Purpose |
|---|---|
| `GetAccountByEmail` | Look up an account by email address |
| `GetAccount` | Look up an account by integer ID |
| `InsertFamily` | Create a new family record |
| `InsertAccount` | Create a new account record |
| `GetDbPathForFamily` | Retrieve the `db_path` for a given `family_id` |
| `InsertRegistryAuthToken` | Store a new (hashed) magic link token |
| `GetRegistryAuthTokenByHash` | Look up a token by its SHA-256 hash |
| `MarkRegistryAuthTokenUsed` | Record when a token was consumed |
| `UpdateAccountLastLogin` | Update the `last_login_at` timestamp |
| `DeleteExpiredRegistryAuthTokens` | Purge expired tokens |

All messages use a `reply_to: Subject(Result(...))` pattern — the caller provides a reply channel and receives the result asynchronously via `process.call`.

---

## Family DB Supervisor (`backend/src/backend/family_db_supervisor.gleam`)

The `FamilyDbSupervisor` is a plain OTP actor (not a static supervisor) that manages a pool of running `FamilyDbActor` processes. It maintains a mapping from `family_id` → `Subject(family_db_actor.Message)`.

### GetOrStart Pattern

When a route handler needs to interact with a family's database, it calls `family_db_supervisor.GetOrStart(family_id, reply_to)`:

1. If an actor for `family_id` is already running, return its `Subject` immediately.
2. If not, spawn a new `FamilyDbActor` for that family, monitor it for crashes, register the `Subject` in the pool map, and return it.

If the `FamilyDbActor` crashes, the supervisor receives a `Down` message via its process monitor selector and removes the entry from the pool map. The next `GetOrStart` call will spawn a fresh actor.

---

## Family DB Actor (`backend/src/backend/family_db_actor.gleam`)

Each `FamilyDbActor` manages a persistent SQLite connection to a single family's database file.

### Startup Sequence

1. Look up the family's `db_path` via the `RegistryActor` (using `GetDbPathForFamily`)
2. Open a SQLite connection to that path (creates the file if absent)
3. Enable foreign keys: `PRAGMA foreign_keys = ON`
4. Run the migration runner (`migrations.run(conn, "priv/migrations/family")`) to initialise the family schema
5. Record the current time as `last_used_at` (used for eviction)
6. Register and begin handling messages

### Message Protocol

| Message | Purpose |
|---|---|
| `Exec` | Run a parrot-generated `:exec` query (no rows returned) |
| `GetLastUsedAt` | Return the Unix millisecond timestamp of the last operation |
| `Shutdown` | Gracefully close the connection and stop the actor |

The `Exec` message accepts the raw parrot 3-tuple `#(String, List(dev.Param), String)` directly, so route handlers can call a parrot-generated function and forward the result to the actor without any intermediate translation.

---

## DB Evictor (`backend/src/backend/db_evictor.gleam`)

The `DbEvictor` is a tail-recursive loop spawned as a linked process after the supervisor starts. Its job is to bound memory usage by evicting `FamilyDbActor` processes that have been idle too long.

### Eviction Logic

On each tick (interval controlled by `config.eviction_check_interval_ms`):

1. Ask the `FamilyDbSupervisor` for the list of all running family actors and their `family_id`s
2. For each actor, call `GetLastUsedAt` to retrieve the idle timestamp
3. Calculate `now_ms - last_used_at`
4. If the idle duration exceeds `config.db_idle_ttl_ms`, send a `Shutdown` message to that actor
5. Sleep for the configured interval, then recurse

This keeps the connection pool bounded without requiring a fixed pool size.

---

## Shared DB Helpers (`backend/src/backend/db.gleam`)

`db.gleam` is a small shared module that bridges **parrot** (the SQL code generator) and **sqlight** (the SQLite library). Both `RegistryActor` and `FamilyDbActor` import it.

### `to_sqlight(param: dev.Param) -> sqlight.Value`

Converts a parrot `Param` union type to the corresponding `sqlight.Value`. Parrot uses its own `dev.Param` type; sqlight has its own `Value` type. This conversion function is the single place where that mapping is defined.

### `exec_query(conn, query) -> Result(List(a), String)`

Runs a parrot-generated `:one` or `:many` query:

```gleam
pub fn exec_query(
  conn: sqlight.Connection,
  query: #(String, List(dev.Param), decode.Decoder(a)),
) -> Result(List(a), String)
```

Parrot generates functions that return a `#(sql_string, params, decoder)` 3-tuple. `exec_query` unpacks the tuple, converts params via `to_sqlight`, runs `sqlight.query`, and maps any error to a plain `String`.

### `exec_command(conn, query) -> Result(Nil, String)`

Runs a parrot-generated `:exec` query (insert/update/delete — no rows returned):

```gleam
pub fn exec_command(
  conn: sqlight.Connection,
  query: #(String, List(dev.Param), String),
) -> Result(Nil, String)
```

The third element of the `:exec` tuple is an empty string (parrot convention); `exec_command` ignores it and uses a `decode.success(Nil)` decoder to discard any incidental result rows.

---

## Parrot Code Generation

[Parrot](https://github.com/lpil/parrot) is the SQL code generator used in Pie Safe. It reads annotated `.sql` files and generates typed Gleam modules.

### SQL Annotation Format

```sql
-- name: GetAccountByEmail :one
SELECT id, family_id, email, role, created_at, last_login_at
FROM accounts
WHERE email = ?;

-- name: InsertAccount :exec
INSERT INTO accounts (family_id, email, role, created_at, last_login_at)
VALUES (?, ?, ?, ?, ?);
```

- `:one` — generates a function returning a typed record and a decoder
- `:many` — generates a function returning `List(T)` and a decoder
- `:exec` — generates a function with no return decoder (insert/update/delete)

### Generated Module Structure

For each `:one` or `:many` query, parrot generates:
- A **record type** named after the query in PascalCase (e.g. `GetAccountByEmail`)
- A **function** returning `#(String, List(dev.Param), decode.Decoder(T))`

For each `:exec` query, parrot generates:
- A **function** returning `#(String, List(dev.Param), String)` (empty string as third element)

### Two Generated Modules

| SQL source | Generated module | Consumer |
|---|---|---|
| `registry/src/sql/registry_queries.sql` | `registry/src/registry/sql.gleam` | `registry_actor.gleam` |
| `backend/src/sql/queries.sql` | `backend/src/backend/sql.gleam` | `family_db_actor.gleam` |

Parrot requires a live SQLite file to introspect the schema before generating. Two separate invocations are needed:

```sh
# From registry/ — needs data/registry.db with schema applied
gleam run -m parrot -- --sqlite data/registry.db

# From backend/ — needs data/family_template.db with schema applied
gleam run -m parrot -- --sqlite data/family_template.db
```

Generated modules are committed to version control and must not be edited by hand.

---

## Migration Runner (`backend/src/backend/migrations.gleam`)

The migration runner provides versioned, forward-only schema migrations with tamper detection via SHA-256 hashing.

### Public API

```gleam
pub fn run(conn: sqlight.Connection, migrations_dir: String) -> Result(Nil, String)
```

Called during actor initialisation, before the actor begins accepting messages. If it returns `Error(String)`, actor init fails and the supervisor handles the crash.

### Migration File Format

Migration files live under `backend/priv/migrations/`:

```
backend/priv/migrations/
  registry/
    001_initial_schema.sql
  family/
    001_initial_schema.sql
```

Filenames must follow the pattern `NNN_description.sql` (zero-padded 3-digit integer prefix). Files not matching this pattern are silently skipped with a log warning.

### Startup Sequence

On each call to `migrations.run/2`:

1. **Bootstrap** — Create `_migrations` table if it does not exist:
   ```sql
   CREATE TABLE IF NOT EXISTS _migrations (
     version    INTEGER PRIMARY KEY,
     sha256     TEXT NOT NULL,
     applied_at TEXT NOT NULL
   );
   ```

2. **Load** — Read all `.sql` files from `migrations_dir` using `simplifile.read_directory` and `simplifile.read`. Parse version numbers. Compute SHA-256 hash of each file's contents (`crypto.hash(crypto.Sha256, ...)` → `bit_array.base16_encode` → lowercase). Sort ascending by version.

3. **Get current version** — `SELECT COALESCE(MAX(version), 0) FROM _migrations`.

4. **Validate applied migrations** — For every migration on disk with `version <= current_version`, retrieve the stored SHA-256 from `_migrations` and compare with the computed hash of the file on disk. A mismatch is a **hard error** — the actor will fail to start. This detects accidental or malicious modification of already-applied migration files.

5. **Apply unapplied migrations** — For each migration with `version > current_version`, in ascending order:
   - `BEGIN` transaction
   - Execute the migration SQL via `sqlight.exec`
   - `INSERT INTO _migrations (version, sha256, applied_at) VALUES (?, ?, ?)`
   - `COMMIT`
   - On any failure: `ROLLBACK` and return `Error(String)` immediately

6. Return `Ok(Nil)` if all steps succeeded.

### Design Decisions

| Decision | Rationale |
|---|---|
| Forward-only migrations | Simplicity; rollbacks are a deployment concern, not a code concern |
| Per-migration transactions | Migrations 1–N committed even if N+1 fails; avoids all-or-nothing risk |
| SHA-256 hash validation | Catches accidental edits to already-applied migrations before they cause silent corruption |
| `simplifile` for I/O | No `@external` FFI needed in `migrations.gleam`; `simplifile` provides `read_directory` and `read` |
| Hashes computed at load time | Single pass over files; hash stored on `Migration` record, not recomputed per step |

---

## Style Conventions

The database layer enforces these conventions throughout:

- **No raw SQL in `.gleam` files** — all queries go through parrot-generated functions. The only exception is the migration runner itself, which runs DDL via `sqlight.exec` (DDL is schema management, not application queries).
- **No deep nesting** — actor initialisers and handlers use `use x <- result.try(...)` chains to stay flat. No function body exceeds 2 levels of `case` nesting.
- **Private helpers** — any logic block longer than ~5 lines is extracted into a named private function (`open_db`, `enable_foreign_keys`, `fetch_db_path`, etc.).
- **`result.try` pipelines** — errors propagate via `Result`, never via exceptions (except during startup where `panic` is intentional).
