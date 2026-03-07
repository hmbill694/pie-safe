# Progress: Registry DB Startup Initialization

- [x] Step 1: Added `envoy = ">= 1.1.0 and < 2.0.0"` to `backend/gleam.toml` [dependencies]
- [x] Step 2: Created `backend/src/backend/config.gleam` — reads REGISTRY_DB_PATH and PORT env vars, returns Config record
- [x] Step 3: Created `backend/src/backend/registry.gleam` — opens registry DB, runs PRAGMA + DDL, closes connection
- [x] Step 4: Replaced `backend/src/backend.gleam` — removed stale code, added config.load() and registry.init(), uses config.port for mist
