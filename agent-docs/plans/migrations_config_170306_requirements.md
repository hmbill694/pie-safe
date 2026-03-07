# Configurable Migration Directories — Requirements

## Background

The migration runner (`backend/src/backend/migrations.gleam`) was implemented with hardcoded directory paths passed from each actor:
- `registry_actor` calls `migrations.run(conn, "priv/migrations/registry")`
- `family_db_actor` calls `migrations.run(conn, "priv/migrations/family")`

These paths need to be configurable via environment variables so that deployments can place migration files wherever makes sense for their environment.

---

## Requirements

### 1. `config.gleam` — Add two new required fields

Add `registry_migrations_dir: String` and `family_migrations_dir: String` to the `Config` type.

Load them from environment variables `REGISTRY_MIGRATIONS_DIR` and `FAMILY_MIGRATIONS_DIR` respectively. Both are **required** — if either is unset, panic at startup with the same pattern used by `REGISTRY_DB_PATH`:

```gleam
panic as "Missing required environment variable: REGISTRY_MIGRATIONS_DIR"
panic as "Missing required environment variable: FAMILY_MIGRATIONS_DIR"
```

Updated `Config` type:
```gleam
pub type Config {
  Config(
    registry_db_path: String,
    registry_migrations_dir: String,
    family_migrations_dir: String,
    port: Int,
    db_idle_ttl_ms: Int,
    eviction_check_interval_ms: Int,
  )
}
```

---

### 2. `backend.gleam` — Thread config through to actors

- Pass `cfg.registry_migrations_dir` to `registry_actor.start` (and `registry_actor.supervised`)
- Pass `cfg.family_migrations_dir` to `family_db_supervisor.supervised`

---

### 3. `registry_actor.gleam` — Accept migrations dir as parameter

- `supervised/2` → `supervised/3`: add `migrations_dir: String` as third parameter
- `start/2` → `start/3`: add `migrations_dir: String` as third parameter
- Replace hardcoded `"priv/migrations/registry"` in the `migrations.run` call with the received `migrations_dir`

---

### 4. `family_db_supervisor.gleam` — Store and thread migrations dir

- `supervised/1` → `supervised/2`: add `family_migrations_dir: String` as second parameter
- `start/1` → `start/2`: add `family_migrations_dir: String` as second parameter
- Add `family_migrations_dir: String` to the `State` type, initialised from the parameter
- In `start_family_actor`, pass `state.family_migrations_dir` through to `family_db_actor.start`
- The `GetOrStart` message handler calls `start_family_actor` — ensure it has access to `state.family_migrations_dir`

---

### 5. `family_db_actor.gleam` — Accept migrations dir as parameter

- `start/2` → `start/3`: add `migrations_dir: String` as third parameter
- Replace hardcoded `"priv/migrations/family"` in the `migrations.run` call with the received `migrations_dir`

---

### 6. `.envrc.sample` — Document new required vars

Add the two new required environment variables to `.envrc.sample` with example values matching the previous defaults:

```sh
export REGISTRY_MIGRATIONS_DIR=priv/migrations/registry
export FAMILY_MIGRATIONS_DIR=priv/migrations/family
```

---

## Files Changed

| File | Change |
|---|---|
| `backend/src/backend/config.gleam` | Add 2 required fields + env var loading |
| `backend/src/backend.gleam` | Pass new config fields to actors |
| `backend/src/backend/registry_actor.gleam` | `start`/`supervised` gain `migrations_dir` param |
| `backend/src/backend/family_db_supervisor.gleam` | `start`/`supervised` gain `family_migrations_dir` param; stored in State |
| `backend/src/backend/family_db_actor.gleam` | `start` gains `migrations_dir` param |
| `.envrc.sample` | Document two new required env vars |

## Out of Scope

- Changes to `migrations.gleam` itself
- Changes to the SQL migration files
- Any change to how migration files are read or validated
