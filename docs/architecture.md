# Pie Safe — Architecture Overview

## What is Pie Safe?

Pie Safe is a family health and information management application. It centralises the kind of information that is typically held in one person's head — the "family manager" — and makes it accessible to the whole family. This includes:

- Medications and prescriptions
- Medical appointments and reminders
- Health providers (doctors, dentists, specialists, pharmacies)
- Allergies and immunizations
- Insurance plans
- Emergency contacts
- Document storage (lab results, insurance cards, referrals, etc.)

The application is built entirely in **Gleam**, a type-safe functional language that compiles to both Erlang (for the backend) and JavaScript (for the frontend).

---

## Monorepo Structure

The repository is a multi-package Gleam monorepo with four sibling packages at the root:

```
pie-safe/
├── core/       # Shared types library (multi-target: Erlang + JS)
├── ui/         # Lustre single-page application (JavaScript target)
├── backend/    # Mist HTTP server + OTP application (Erlang target)
└── registry/   # Central registry database package (Erlang target)
```

### `core`
A pure Gleam library with no target lock. Contains shared types used by both the frontend and backend. Has no dependencies beyond `gleam_stdlib`.

### `ui`
The client-side single-page application. Compiled to JavaScript and served as a static bundle from the backend. Key characteristics:
- Built with **Lustre** (Gleam's Elm-Architecture frontend framework)
- Client-side URL routing via **modem**
- HTTP effects via **lustre_http**
- Tailwind CSS for styling
- Build output (`ui.js` + `ui.css`) is written directly into `backend/priv/static/`

### `backend`
The Erlang OTP application. Handles all HTTP requests, database access, and business logic. Key characteristics:
- HTTP server via **Mist** (listens on configurable `PORT`)
- SQLite database access via **sqlight** (Erlang NIF)
- Type-safe SQL queries via **parrot** (sqlc-style code generator)
- OTP supervisor tree for database connection management
- Serves the Lustre SPA bundle as static files

### `registry`
A separate Gleam package that owns the SQL schema and generated query module for the central registry database. It is a path dependency of `backend`. This separation keeps registry SQL types cleanly isolated from the per-family SQL types.

---

## Tech Stack

| Layer | Technology | Notes |
|---|---|---|
| Language | Gleam | Type-safe functional language on BEAM/JS |
| Frontend framework | Lustre | Elm-architecture SPA |
| HTTP server | Mist | Gleam-native HTTP server |
| Database | SQLite (via sqlight) | One file per family + one registry file |
| SQL code-gen | Parrot | Generates typed Gleam from annotated `.sql` files |
| OTP | gleam_otp | Actors, supervisors, process registry |
| Auth | Magic links + JWT (HS256) | Passwordless; sessions via HttpOnly cookie |
| Styling | Tailwind CSS | Integrated via lustre_dev_tools |
| Migrations | Custom runner | Versioned `.sql` files with SHA-256 hash validation |

---

## Two-Database Architecture

The most distinctive architectural decision in Pie Safe is the **two-database design**:

### Registry Database (`data/registry.db`)
A single, application-wide SQLite file that acts as the system's directory. It stores:
- **`families`** — one row per registered family group, including the path to that family's database file
- **`accounts`** — login credentials (email, role, family association) for all users
- **`registry_auth_tokens`** — magic link tokens, used *before* a session is established

The registry database is opened once at startup by the `RegistryActor` OTP process and kept open for the lifetime of the application.

### Per-Family Databases (`data/<uuid>.db`)
Each family has its own isolated SQLite file. This provides:
- **Complete data isolation** — no cross-tenant data access is possible at the SQL level
- **No `family_id` foreign keys** — the database boundary itself enforces tenant separation
- **Simple backup and portability** — a family's entire data is a single file

Per-family databases are opened on-demand by `FamilyDbActor` processes, managed by the `FamilyDbSupervisor`, and evicted from memory after a configurable idle period by the `DbEvictor`.

---

## Request Flow

```
Browser
  │
  │  HTTP request
  ▼
Mist HTTP Server (backend.gleam)
  │
  ├─ GET /          → serves index.html (inline constant)
  ├─ GET /static/*  → serves priv/static/ files (ui.js, ui.css)
  ├─ POST /api/auth/register    ─┐
  ├─ POST /api/auth/magic-link  ─┤─ auth.gleam handler
  ├─ GET  /api/auth/verify      ─┤   (uses RegistryActor + FamilyDbSupervisor)
  ├─ GET  /api/auth/me          ─┘
  └─ GET  /*         → serves index.html (SPA catch-all)
```

Once the SPA is loaded in the browser, it handles client-side routing:

```
Browser URL changes
  │
  ▼
modem (URL router)
  │
  ├─ /sign-up  → SignUp page
  ├─ /sign-in  → SignIn page
  └─ /home     → Home page (fetches /api/auth/me to verify session)
```

---

## OTP Supervisor Tree

The backend is structured as an OTP application with a supervisor tree that ensures fault tolerance:

```
main() in backend.gleam
  │
  ├─ config.load()           — reads env vars, panics if missing
  │
  └─ static_supervisor (OneForOne)
        ├─ RegistryActor      — persistent registry.db connection, named process
        └─ FamilyDbSupervisor — pool actor for per-family DB connections, named process

DbEvictor (linked process) — periodically evicts idle family DB connections
```

Named process discovery uses `process.Name` values created once in `main()`, allowing any module to look up a running actor by name without passing `Subject` values around.

---

## Data Model Overview

### Registry Database Tables

| Table | Purpose |
|---|---|
| `families` | One row per family group; holds `db_path` to the family's SQLite file |
| `accounts` | Email-based accounts; each linked to a `family_id` |
| `registry_auth_tokens` | Magic link tokens (pre-login, stored as SHA-256 hashes) |

### Per-Family Database Tables

| Category | Tables |
|---|---|
| Auth & Users | `members`, `auth_tokens` |
| Health Providers | `providers`, `member_providers` |
| Appointments | `appointments`, `appointment_reminders` |
| Medications | `medications`, `member_medications` |
| Allergies | `allergies` |
| Immunizations | `immunizations` |
| Insurance | `insurance_plans`, `member_insurance` |
| Emergency Contacts | `emergency_contacts` |
| Documents | `documents` |

### Key Data Modelling Decisions

- **`members` vs `accounts`** — "accounts" live in the registry and represent login identities. "Members" live in the family DB and represent people (including managed profiles like children who cannot log in themselves, denoted by `is_managed = 1`).
- **All datetimes as `TEXT`** — stored as ISO 8601 strings. Booleans as `INTEGER` (0/1). Money as `REAL`. UUIDs for family IDs as `TEXT PRIMARY KEY`.
- **Documents are metadata only** — actual file bytes are stored externally (e.g. S3); the `storage_path` column holds the reference.

---

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `REGISTRY_DB_PATH` | Yes | Path to the registry SQLite file (e.g. `data/registry.db`) |
| `PORT` | Yes | HTTP port for the Mist server (e.g. `3000`) |
| `JWT_SECRET` | Yes | HS256 signing secret for session JWTs |

The backend panics at startup with a descriptive message if any required variable is missing.

---

## Development Workflow

### Starting the backend
```sh
# From repo root
source .envrc
cd backend && gleam run
```

### Building the frontend
```sh
# From ui/ directory
gleam run -m lustre/dev build --outdir=../backend/priv/static
```

### Running both together
```sh
# From repo root (if dev.sh is configured)
./dev.sh
```

The backend serves the compiled frontend bundle from `backend/priv/static/`. On every navigation, the browser loads the Lustre SPA, which handles routing client-side. API calls go back to the same origin, avoiding CORS concerns.
