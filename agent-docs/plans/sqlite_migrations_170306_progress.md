# SQLite Migration Runner — Progress

- [x] Step 1: Updated `backend/gleam.toml` to add `simplifile` and `gleam_crypto` as explicit dependencies
- [x] Step 2.1: Created `backend/priv/migrations/registry/` directory (via SQL file creation)
- [x] Step 2.2: Created `backend/priv/migrations/family/` directory (via SQL file creation)
- [x] Step 3.1: Created `backend/priv/migrations/registry/001_initial_schema.sql` with registry DDL
- [x] Step 3.2: Created `backend/priv/migrations/family/001_initial_schema.sql` with family DDL
- [x] Step 4: Implemented `backend/src/backend/migrations.gleam` with all functions (compute_hash, parse_version, load_migrations, bootstrap_migrations_table, get_current_version, get_stored_hash, validate_applied_migration, apply_migration, run)
- [x] Step 5.1: Added `import backend/migrations` to `registry_actor.gleam`
- [x] Step 5.2: Deleted `const registry_ddl` from `registry_actor.gleam`
- [x] Step 5.3: Deleted `fn run_ddl` from `registry_actor.gleam`
- [x] Step 5.4: Replaced `run_ddl(conn)` with `migrations.run(conn, "priv/migrations/registry")` in `registry_actor.gleam`
- [x] Step 6.1: Added `import backend/migrations` to `family_db_actor.gleam`
- [x] Step 6.2: Deleted `const family_ddl` from `family_db_actor.gleam`
- [x] Step 6.3: Deleted `fn run_family_ddl` from `family_db_actor.gleam`
- [x] Step 6.4: Replaced `run_family_ddl(conn)` with `migrations.run(conn, "priv/migrations/family")` in `family_db_actor.gleam`
