# Progress: migrations_config_170306

- [x] Step 1: Updated `config.gleam` — added `registry_migrations_dir` and `family_migrations_dir` fields to `Config` type, loaded from `REGISTRY_MIGRATIONS_DIR` and `FAMILY_MIGRATIONS_DIR` env vars with panic on missing
- [x] Step 2: Updated `registry_actor.gleam` — added `migrations_dir: String` as third parameter to both `supervised/3` and `start/3`; replaced hardcoded `"priv/migrations/registry"` with `migrations_dir`
- [x] Step 3: Updated `family_db_actor.gleam` — added `migrations_dir: String` as third parameter to `start/3`; replaced hardcoded `"priv/migrations/family"` with `migrations_dir`
- [x] Step 4: Updated `family_db_supervisor.gleam` — added `family_migrations_dir: String` to `State` type, `start/2`, `supervised/2`, and `start_family_actor/3`; threaded through to `family_db_actor.start`
- [x] Step 5: Updated `backend.gleam` — passed `cfg.registry_migrations_dir` to `registry_actor.start` and `cfg.family_migrations_dir` to `family_db_supervisor.supervised`
- [x] Step 6: Updated `.envrc.sample` — added `REGISTRY_MIGRATIONS_DIR` and `FAMILY_MIGRATIONS_DIR` exports with default values
