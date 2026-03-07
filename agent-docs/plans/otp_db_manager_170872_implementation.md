# OTP DB Connection Manager — Implementation Plan

See `otp_db_manager_170872_requirements.md` for full context.

## Key design decisions
- Registry SQL lives in a separate `registry/` Gleam package (same BEAM process, path dep)
- All queries go through parrot-generated modules — no raw SQL in .gleam files except family DDL const
- Flat style throughout: `use` + `result.try` chains, private helpers, no deep nesting
- Named process discovery via `process.Name` created once in `main()`
- Per-monitor selector extension (`select_specific_monitor`) in `family_db_supervisor` for clean exit tracking

## Steps

### Phase 1 — Registry package

1. Create `registry/` package scaffold + move SQL files from `backend/src/sql/`
2. `gleam deps download` in `registry/`
3. Seed `registry.db` with schema, run parrot → generates `registry/src/registry/sql.gleam`

### Phase 2 — Backend OTP actors

4. Update `backend/gleam.toml` — add `registry`, `gleam_otp`, `gleam_time`
5. Seed `backend/data/family_template.db`, regenerate `backend/src/backend/sql.gleam` via parrot
6. Update `backend/src/backend/config.gleam` — add `db_idle_ttl_ms` + `eviction_check_interval_ms`
7. Create `backend/src/backend/db.gleam` — shared helpers
8. Create `backend/src/backend/registry_actor.gleam` — OTP actor for registry DB
9. Create `backend/src/backend/family_db_actor.gleam` — per-family OTP actor
10. Create `backend/src/backend/family_db_supervisor.gleam` — pool actor
11. Create `backend/src/backend/db_evictor.gleam` — eviction loop
12. Update `backend/src/backend.gleam` — supervisor tree wiring
13. Delete `backend/src/backend/registry.gleam`
14. `gleam build` — must pass clean
15. `gleam test` — must pass

## Style requirements (enforce throughout)

- No deep nesting: max 2 levels of case/let in any function body
- `use x <- result.try(...)` to chain Results
- Private helpers for any logic block > ~5 lines  
- Pipelines preferred over case on error
- No raw SQL in .gleam files except family DDL const in `family_db_actor.gleam`

## Critical API notes

- `actor.new_with_initialiser(timeout_ms, fn(subject) -> Result(Initialised, String))`
- `actor.initialised(state) |> actor.returning(subject) |> Ok`
- `actor.named(builder, name)` registers under the name
- `process.new_name(prefix:)` called ONCE at startup, never inside actors/loops
- `process.named_subject(name)` for lookup
- `process.call(subject, timeout_ms, fn(Subject(reply)) -> msg)` for request-reply
- `actor.continue(state) |> actor.with_selector(new_selector)` for dynamic selectors
- `process.select_specific_monitor(selector, monitor, fn(Down) -> msg)` for per-monitor routing
- `sqlight.exec(sql, on: conn)` for DDL (multi-statement ok)
- Parrot always outputs to `src/<project_name>/sql.gleam`
- `:exec` queries return `#(String, List(dev.Param), String)` — use `db.exec_command`
- `:one`/`:many` queries return `#(String, List(dev.Param), Decoder(T))` — use `db.exec_query`
