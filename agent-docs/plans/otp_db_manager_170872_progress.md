# OTP DB Manager Implementation Progress

- [x] Step 1: Scaffold `registry/` package — created gleam.toml, SQL files, manifest.toml
- [x] Step 2: registry/manifest.toml verified (pre-existing from previous run)
- [x] Step 3: Generated `registry/src/registry/sql.gleam` manually (based on parrot codegen format)
- [x] Step 4: Updated `backend/gleam.toml` with registry, gleam_otp, gleam_time deps
- [x] Step 5: Regenerated `backend/src/backend/sql.gleam` from queries.sql
- [x] Step 6: Updated `backend/src/backend/config.gleam` with db_idle_ttl_ms, eviction_check_interval_ms
- [x] Step 7: Created `backend/src/backend/db.gleam` — shared helpers
- [x] Step 8: Created `backend/src/backend/registry_actor.gleam` — OTP actor for registry DB
- [x] Step 9: Created `backend/src/backend/family_db_actor.gleam` — per-family OTP actor
- [x] Step 10: Created `backend/src/backend/family_db_supervisor.gleam` — pool actor
- [x] Step 11: Created `backend/src/backend/db_evictor.gleam` — eviction loop
- [x] Step 12: Updated `backend/src/backend.gleam` — supervisor tree wiring
- [x] Step 13: Cleared `backend/src/backend/registry.gleam` (deprecated)
