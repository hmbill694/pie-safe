# pie-safe — Gleam Monorepo (Hello World) Requirements

## Repo structure
Three sibling Gleam packages at the repo root:
```
pie-safe/
├── ui/        # Lustre SPA  (JavaScript target)
├── backend/   # Mist HTTP server (Erlang target)
└── core/      # Shared types (multi-target library)
```

## `core` package
- Pure Gleam library, no target lock (works on both JS & Erlang)
- Single demo type: `pub type Greeting { Greeting(message: String) }` in `src/core/greeting.gleam`
- No extra dependencies beyond `gleam_stdlib`

## `ui` package (JavaScript target)
- `target = "javascript"` in `gleam.toml`
- Dependencies: `lustre`, `lustre_dev_tools` (dev), `core` (path: `"../core"`)
- Tailwind CSS wired in via `lustre_dev_tools` (`lustre.json` config with Tailwind enabled)
- `src/ui.gleam` — a `lustre.simple` app that:
  - Imports `core/greeting.Greeting` and constructs one with `"Hello, World!"`
  - Renders a full-page centered layout with a styled heading using Tailwind classes
- Build output (JS bundle + CSS) targets `../backend/priv/static/`

## `backend` package (Erlang target)
- `target = "erlang"` in `gleam.toml`
- Dependencies: `mist`, `gleam_erlang`, `gleam_http`, `sqlight`, `parrot`, `core` (path: `"../core"`)
- `src/backend.gleam` — Mist server on port **3000** that:
  - Serves `GET /` → inlines an `index.html` pointing at `/static/ui.js` and `/static/ui.css`
  - Serves `GET /static/*` → files from `priv/static/`
- SQLite wiring:
  - `src/sql/schema.sql` — a minimal `CREATE TABLE IF NOT EXISTS greetings (id INTEGER PRIMARY KEY, message TEXT NOT NULL);`
  - `src/sql/queries.sql` — a single annotated query `-- name: ListGreetings :many  SELECT * FROM greetings;`
  - Parrot code-gen is set up (sqlc config + parrot dependency); the generated `sql.gleam` is committed
  - The generated query is called at startup (opens a SQLite file `data/app.db`) but the result is only logged, not wired into HTTP responses yet

## Hello World goal
1. In `ui/`: `gleam run -m lustre/dev build --outdir=../backend/priv/static` → produces `ui.js` + `ui.css`
2. In `backend/`: `gleam run` → server starts on http://localhost:3000
3. Browser shows a Tailwind-styled **"Hello, World!"** heading rendered by Lustre
