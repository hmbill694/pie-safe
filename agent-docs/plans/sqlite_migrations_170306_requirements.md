# SQLite Migration Runner — Requirements

## Background

pie-safe is a Gleam/OTP app using SQLite (via `sqlight`). Two types of databases are managed:
- A singleton **registry DB** opened by `registry_actor` at startup
- Per-family **family DBs** opened lazily by `family_db_actor` on first access

Currently, both actors initialise their databases by running a large embedded DDL string via `sqlight.exec/2`. There is no versioning, no migration history, and no safe path for future schema changes.

The goal is to replace this ad-hoc DDL approach with a lightweight, versioned SQLite migration runner built in-house (Cigogne was evaluated and rejected as it is Postgres-only via `pog`).

---

## Requirements

### 1. New module: `backend/src/backend/migrations.gleam`

A shared migration runner with the following public API:

```gleam
pub fn run(conn: sqlight.Connection, migrations_dir: String) -> Result(Nil, String)
```

**Behaviour:**

1. **Bootstrap the migrations table** — If a `_migrations` table does not exist on `conn`, create it:
   ```sql
   CREATE TABLE IF NOT EXISTS _migrations (
     version    INTEGER PRIMARY KEY,
     applied_at TEXT NOT NULL
   );
   ```

2. **Read migration files** — Read all `.sql` files from `migrations_dir` at runtime. The directory path is relative to the application's working directory (the `backend` package root). Use Erlang's `:file` module (via an `@external` FFI call) or `simplifile` if already available.

3. **Parse version numbers** — Extract the integer version from each filename using the format `NNN_description.sql` (zero-padded 3-digit prefix, e.g. `001_initial_schema.sql`). Filenames that do not match this format are ignored with a warning logged to stdout.

4. **Sort migrations** — Sort parsed migrations by version number ascending.

5. **Determine current version** — Query `SELECT MAX(version) FROM _migrations`. If the table is empty, treat current version as `0`.

6. **Apply unapplied migrations** — For each migration with `version > current_version`, in ascending order:
   - Wrap the SQL in an explicit SQLite transaction (`BEGIN` / `COMMIT`, rolled back on error via `ROLLBACK`)
   - Execute the migration SQL
   - On success, `INSERT INTO _migrations (version, applied_at) VALUES (?, ?)` with the current UTC timestamp as an ISO-8601 string
   - On failure, return an `Error(String)` immediately (do not continue applying remaining migrations)

7. **Return** `Ok(Nil)` if all unapplied migrations were applied successfully (or if there were none to apply).

**Notes:**
- Transactions are per-migration (not all-or-nothing across all pending migrations). If migration 3 fails, migrations 1 and 2 are already committed and recorded.
- There is no rollback/down support. Migrations are forward-only.
- The runner does not validate hashes or detect file modifications. Version number is the sole identity.

---

### 2. Migration files

Create the following directory structure and files:

**`backend/priv/migrations/registry/001_initial_schema.sql`**
- Contents: the current `registry_ddl` constant from `registry_actor.gleam` (the `PRAGMA foreign_keys = ON` plus the three `CREATE TABLE IF NOT EXISTS` statements for `families`, `accounts`, and `registry_auth_tokens`)

**`backend/priv/migrations/family/001_initial_schema.sql`**
- Contents: the current `family_ddl` constant from `family_db_actor.gleam` (the `PRAGMA foreign_keys = ON` plus all 14 `CREATE TABLE IF NOT EXISTS` statements)

---

### 3. Update `registry_actor.gleam`

- Remove the `registry_ddl` const
- Remove the `run_ddl/1` private function
- In the `start/2` initialiser, replace `use _ <- result.try(run_ddl(conn))` with:
  ```gleam
  use _ <- result.try(migrations.run(conn, "priv/migrations/registry"))
  ```
- Add `import backend/migrations` at the top

---

### 4. Update `family_db_actor.gleam`

- Remove the `family_ddl` const
- Remove the `run_family_ddl/1` private function
- In the `start/2` initialiser, replace `use _ <- result.try(run_family_ddl(conn))` with:
  ```gleam
  use _ <- result.try(migrations.run(conn, "priv/migrations/family"))
  ```
- Add `import backend/migrations` at the top

---

## File Layout After Implementation

```
backend/
  priv/
    migrations/
      registry/
        001_initial_schema.sql
      family/
        001_initial_schema.sql
  src/
    backend/
      migrations.gleam          ← new
      registry_actor.gleam      ← modified
      family_db_actor.gleam     ← modified
      db.gleam                  ← unchanged
      ...
```

---

## Hash Validation

Each applied migration's SHA-256 hash is stored in `_migrations` alongside the version number. On subsequent startups, the runner re-hashes each migration file on disk and compares it against the stored hash for that version. A mismatch is a **hard error** — `migrations.run/2` returns `Error(String)`, causing actor init to fail.

**Details:**
- What is hashed: the raw file contents as read from disk (no normalisation)
- Algorithm: SHA-256 via `gleam_crypto` (added as an explicit dependency to `gleam.toml`)
- Storage: hex-encoded string stored in a new `sha256` column on `_migrations`
- `simplifile` is also added as an explicit dependency to `gleam.toml` (already resolved transitively via `parrot`; adding it explicitly for direct use in `migrations.gleam`)

**Updated `_migrations` table schema:**
```sql
CREATE TABLE IF NOT EXISTS _migrations (
  version    INTEGER PRIMARY KEY,
  sha256     TEXT NOT NULL,
  applied_at TEXT NOT NULL
);
```

**Startup validation flow (for already-applied migrations):**
1. For each migration file on disk whose `version <= current_version`, compute its SHA-256 hash
2. Query the stored `sha256` from `_migrations` for that version
3. If hashes differ → return `Error("Migration <version> has been modified after being applied. Hash mismatch: expected <stored>, got <computed>.")`
4. If hashes match → continue

---

## Out of Scope

- Down/rollback migrations
- CLI tooling for creating new migration files
- Any changes to the parrot codegen workflow or `.sql` query files
- Changes to the `registry` package
