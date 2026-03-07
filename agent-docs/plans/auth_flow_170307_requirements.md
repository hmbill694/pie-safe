# Requirements: End-to-End Authentication Flow

## Overview

Wire up the full magic-link authentication flow across backend and frontend. The backend gains 4 new API routes; the frontend home page is updated to use a cookie-backed session instead of localStorage.

---

## Backend Routes

### POST /api/auth/register
- **Body:** `{ "first_name": string, "last_name": string, "family_name": string, "email": string }`
- **Logic:**
  1. Check if email already exists in registry DB via `GetAccountByEmail` — return 409 if found
  2. Generate a UUID for `family_id`
  3. Create the family row in registry: `families(id, name=family_name, db_path="data/<uuid>.db", status="active", created_at)`
  4. Create the account row in registry: `accounts(family_id, email, role="admin", created_at)`
  5. Start (or get) the family DB actor for the new family, insert a `members` row: `(email, first_name, last_name, role="admin", is_managed=0, created_at, updated_at)`
  6. Generate a 32-byte random token → hex-encode → store SHA-256 hash in `registry_auth_tokens(account_id, token_hash, token_type="magic_link", expires_at=now+15min, used_at=null, created_at)`
  7. Log to stdout: `[magic-link] http://localhost:3000/api/auth/verify?token=<raw_hex_token>`
  8. Return `200 { "ok": true }`
- **Errors:** 409 if email exists; 500 on any other failure

### POST /api/auth/magic-link
- **Body:** `{ "email": string }`
- **Logic:**
  1. Look up account by email in registry DB
  2. If not found: return 404 `{ "error": "no account found for that email" }`
  3. Generate token, store hash in `registry_auth_tokens`, log magic link URL to stdout
  4. Return `200 { "ok": true }`

### GET /api/auth/verify?token=<token>
- **Logic:**
  1. SHA-256 hash the raw token from the query param
  2. Look up the hash in `registry_auth_tokens` — 400 if not found
  3. Validate `used_at IS NULL` — 400 "token already used" if not
  4. Validate `expires_at > now` — 400 "token expired" if not
  5. Mark token used (`used_at = now`)
  6. Look up the account (`account_id` from the token row)
  7. Update `accounts.last_login_at = now`
  8. Sign a JWT: `{ "family_id": string, "account_id": int, "email": string, "role": string }`, expiry 24h, HS256, secret from `JWT_SECRET` env var
  9. Set `Set-Cookie: pie_safe_session=<jwt>; HttpOnly; Path=/; SameSite=Lax`
  10. Redirect to `/home` (302)

### GET /api/auth/me
- **Logic:**
  1. Read `Cookie: pie_safe_session=<jwt>` from request headers
  2. Verify and decode the JWT — 401 if missing, invalid, or expired
  3. Return `200 { "email": string, "role": string }`

---

## JWT Details
- Algorithm: HS256 (HMAC-SHA256)
- Header: `{"alg":"HS256","typ":"JWT"}`
- Payload fields: `family_id`, `account_id`, `email`, `role`, `exp` (Unix timestamp)
- Secret: `JWT_SECRET` env var — panic on startup if missing
- Implementation: hand-rolled in `backend/src/backend/jwt.gleam` using `gleam_crypto` (already a dependency) for the HMAC, and `gleam_stdlib`'s `gleam/base` for base64url encoding

## Magic Link Token Details
- 32 random bytes via `crypto.strong_random_bytes(32)`
- Hex-encoded with `bit_array.base16_encode` → lowercase → 64-char string sent in URL
- Stored as SHA-256 hash of the raw bytes
- Expiry: 15 minutes from creation

---

## Frontend: Home Page Update

Replace the localStorage-based auth check with a fetch to `/api/auth/me`:

- In `ui/src/pages/home.gleam`:
  - Remove the localStorage FFI import and JWT decode logic
  - On `init`, dispatch a `CheckSession` effect: `GET /api/auth/me` via `lustre_http`
  - New `Msg` variants: `GotSession(Result(SessionData, lustre_http.HttpError))`
  - `SessionData` is a record with `email: String` and `role: String`
  - On `GotSession(Ok(data))`: transition to `Authenticated(email: data.email)`
  - On `GotSession(Error(_))`: redirect to `/sign-in` via `modem.replace`
  - The sign-out button should call `POST /api/auth/sign-out` (which clears the cookie server-side) then redirect — or simply redirect to `/sign-in` for now (cookie expiry handles the rest)
  - The `Unauthenticated` model variant becomes `Loading` (while the `/me` fetch is in flight) and `Unauthenticated` (for redirect)

---

## New Files (Backend)

| File | Purpose |
|---|---|
| `backend/src/backend/token.gleam` | `generate() -> String` and `hash(raw: String) -> String` |
| `backend/src/backend/jwt.gleam` | `sign(claims, secret) -> String` and `verify(token, secret) -> Result(Claims, String)` |
| `backend/src/backend/auth.gleam` | Handler functions for all 4 routes |

## Modified Files (Backend)

| File | Change |
|---|---|
| `backend/src/backend/registry_actor.gleam` | Add messages: `InsertRegistryAuthToken`, `GetRegistryAuthTokenByHash`, `MarkRegistryAuthTokenUsed`, `UpdateAccountLastLogin`, `GetAccount` |
| `backend/src/backend/family_db_actor.gleam` | Add `InsertMember` message (or use existing `Exec` with a raw command) |
| `backend/src/backend/config.gleam` | Add `jwt_secret: String` field |
| `backend/src/backend.gleam` | Wire `/api/auth/*` routes; pass `cfg`, `registry_name`, `supervisor_name` into handler |
| `.envrc` | Add `JWT_SECRET=dev-secret-change-me` |
| `.envrc.sample` | Add `JWT_SECRET=` |

## Modified Files (Frontend)

| File | Change |
|---|---|
| `ui/src/pages/home.gleam` | Replace localStorage/JWT decode with `GET /api/auth/me` fetch |
| `ui/src/ffi/local_storage.gleam` | May become unused — keep for now |

---

## Notes
- No `gleam_json` parsing needed for JWT — implement base64url encode/decode manually (only ASCII JSON payloads)
- The `family_db_actor` already has an `Exec` message that accepts a raw `#(String, List(Param), String)` tuple — use the existing `family/sql.gleam` generated `insert_member` function for inserting the first member
- Check if `family/sql.gleam` has `insert_member` — if not, write the SQL inline via `Exec`
- The `gleam_time` package is available for timestamps; use `timestamp.system_time() |> timestamp.to_rfc3339(calendar.utc_offset)` for datetime strings
- For Unix epoch seconds (JWT `exp`): use `gleam_time`'s timestamp or the Erlang FFI `os:system_time(second)`
