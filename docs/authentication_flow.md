# Pie Safe — Authentication Flow

## Overview

Pie Safe uses **passwordless magic-link authentication**. There are no passwords. When a user wants to sign in, they provide their email address; the server generates a short-lived one-time token, logs the login URL to stdout (in development), and the user clicks the link to establish a session.

Sessions are maintained via an **HttpOnly JWT cookie** (`pie_safe_session`). The JWT is verified on every protected request server-side; the frontend checks session validity by calling `/api/auth/me`.

---

## Two-Database Auth Split

Authentication spans both databases:

| Stage | Database | Table |
|---|---|---|
| Pre-login (token issuance & verification) | `registry.db` | `registry_auth_tokens` |
| Post-login (session, refresh tokens) | `data/<uuid>.db` | `auth_tokens` |

This split is intentional: magic link tokens must be validated *before* we know which family database to open (the family DB path comes from the registry). Once a session is established, the JWT encodes the `family_id`, which identifies which family DB to use for all subsequent requests.

---

## Registration Flow (`POST /api/auth/register`)

New users register by providing their name, family name, and email.

```
Client                          Backend                        Databases
  │                               │                                │
  │  POST /api/auth/register      │                                │
  │  { first_name, last_name,     │                                │
  │    family_name, email }       │                                │
  │──────────────────────────────►│                                │
  │                               │  GetAccountByEmail(email)      │
  │                               │───────────────────────────────►│ registry.db
  │                               │◄───────────────────────────────│
  │                               │  (None — email is new)         │
  │                               │                                │
  │                               │  uuid.v4_string() → family_id  │
  │                               │  InsertFamily(id, name,        │
  │                               │    db_path="data/<uuid>.db")   │
  │                               │───────────────────────────────►│ registry.db
  │                               │                                │
  │                               │  InsertAccount(family_id,      │
  │                               │    email, role="admin")        │
  │                               │───────────────────────────────►│ registry.db
  │                               │                                │
  │                               │  GetOrStart(family_id) →       │
  │                               │  FamilyDbActor spawned         │
  │                               │  InsertMember(email,           │
  │                               │    first_name, last_name,      │
  │                               │    role="admin", is_managed=0) │
  │                               │───────────────────────────────►│ data/<uuid>.db
  │                               │                                │
  │                               │  generate token (32 bytes)     │
  │                               │  store SHA-256 hash            │
  │                               │  InsertRegistryAuthToken(...)  │
  │                               │───────────────────────────────►│ registry.db
  │                               │                                │
  │                               │  log to stdout:                │
  │                               │  [magic-link] http://...       │
  │                               │                                │
  │◄──────────────────────────────│                                │
  │  200 { "ok": true }           │                                │
```

**Error cases:**
- `409 Conflict` — email already registered (`GetAccountByEmail` returned a row)
- `500 Internal Server Error` — any database failure

---

## Sign-In Flow (`POST /api/auth/magic-link`)

Existing users request a new magic link.

```
Client                          Backend                        registry.db
  │                               │                                │
  │  POST /api/auth/magic-link    │                                │
  │  { "email": "..." }           │                                │
  │──────────────────────────────►│                                │
  │                               │  GetAccountByEmail(email)      │
  │                               │───────────────────────────────►│
  │                               │◄───────────────────────────────│
  │                               │                                │
  │                               │  (if not found → 404)          │
  │                               │                                │
  │                               │  generate token, store hash,   │
  │                               │  log magic link to stdout      │
  │                               │                                │
  │◄──────────────────────────────│                                │
  │  200 { "ok": true }           │                                │
```

**Error cases:**
- `404 Not Found` — email not registered: `{ "error": "no account found for that email" }`

---

## Token Verification Flow (`GET /api/auth/verify?token=<token>`)

The user clicks the magic link from their email (or stdout in dev). This is the only step that creates a session.

```
Client                          Backend                        Databases
  │                               │                                │
  │  GET /api/auth/verify         │                                │
  │  ?token=<64-char hex>         │                                │
  │──────────────────────────────►│                                │
  │                               │  SHA-256 hash the raw token    │
  │                               │  GetRegistryAuthTokenByHash    │
  │                               │───────────────────────────────►│ registry.db
  │                               │◄───────────────────────────────│
  │                               │                                │
  │                               │  Validate:                     │
  │                               │  - token found?                │
  │                               │  - used_at IS NULL?            │
  │                               │  - expires_at > now?           │
  │                               │                                │
  │                               │  MarkRegistryAuthTokenUsed     │
  │                               │───────────────────────────────►│ registry.db
  │                               │                                │
  │                               │  GetAccount(account_id)        │
  │                               │───────────────────────────────►│ registry.db
  │                               │◄───────────────────────────────│
  │                               │                                │
  │                               │  UpdateAccountLastLogin(now)   │
  │                               │───────────────────────────────►│ registry.db
  │                               │                                │
  │                               │  jwt.sign(Claims{              │
  │                               │    family_id, account_id,      │
  │                               │    email, role, exp: now+24h   │
  │                               │  }, JWT_SECRET)                │
  │                               │                                │
  │◄──────────────────────────────│                                │
  │  302 Redirect → /home         │                                │
  │  Set-Cookie: pie_safe_session=<jwt>; HttpOnly; Path=/;         │
  │             SameSite=Lax      │                                │
```

**Error cases:**
- `400 Bad Request` — token not found, already used, or expired

---

## Session Check Flow (`GET /api/auth/me`)

Used by the frontend on every page load to verify the session is still valid.

```
Client                          Backend
  │                               │
  │  GET /api/auth/me             │
  │  Cookie: pie_safe_session=<jwt>
  │──────────────────────────────►│
  │                               │  parse Cookie header
  │                               │  cookie.parse(...) → find "pie_safe_session"
  │                               │  jwt.verify(token, JWT_SECRET)
  │                               │  check exp > now
  │                               │
  │◄──────────────────────────────│
  │  200 { "email": "...",        │
  │        "role": "admin" }      │
```

**Error cases:**
- `401 Unauthorized` — cookie missing, JWT invalid, or JWT expired

---

## Token Security

### Generation

```gleam
// token.gleam
pub fn generate() -> String {
  crypto.strong_random_bytes(32)
  |> bit_array.base16_encode
  |> string.lowercase
  // → 64-character lowercase hex string (256 bits of entropy)
}

pub fn hash(raw: String) -> String {
  bit_array.from_string(raw)
  |> crypto.hash(crypto.Sha256, _)
  |> bit_array.base16_encode
  |> string.lowercase
  // → SHA-256 hash of the raw token, stored in DB
}
```

| Property | Value |
|---|---|
| Token size | 32 random bytes (256 bits) |
| Wire format | 64-character lowercase hex string |
| Storage format | SHA-256 hash of the raw bytes (never stored raw) |
| Expiry | 15 minutes from creation |
| One-time use | `used_at` column set on first use; subsequent uses rejected |

### JWT Signing (HS256)

JWTs are hand-rolled in `backend/src/backend/jwt.gleam` using `gleam_crypto` for HMAC and `gleam_stdlib`'s `bit_array` for base64url encoding. No third-party JWT library is used.

**JWT Structure:**

```
Header:  { "alg": "HS256", "typ": "JWT" }
Payload: {
  "family_id":  "<uuid>",
  "account_id": <int>,
  "email":      "<email>",
  "role":       "admin" | "member",
  "exp":        <unix timestamp seconds>
}
Signature: HMAC-SHA256(base64url(header) + "." + base64url(payload), JWT_SECRET)
```

**Security properties:**
- **Timing-safe signature comparison** — `crypto.secure_compare/2` is used when validating the signature to prevent timing attacks.
- **Base64url encoding** — uses `bit_array.base64_url_encode(bits, False)` (no padding, URL-safe alphabet).
- **Header and payload built with `gleam_json`** — no string concatenation for JSON construction.
- **Secret from environment** — `JWT_SECRET` env var; the backend panics at startup if it is missing.

**JWT Expiry:** 24 hours from issuance.

---

## Session Cookie

The session cookie is set on successful token verification:

```
Set-Cookie: pie_safe_session=<jwt>; HttpOnly; Path=/; SameSite=Lax
```

| Attribute | Value | Rationale |
|---|---|---|
| `HttpOnly` | Yes | Prevents JavaScript from reading the cookie (XSS protection) |
| `Path=/` | Yes | Cookie sent on all requests to the origin |
| `SameSite=Lax` | Yes | Sent on top-level navigations; protects against CSRF |
| `Secure` | Not yet set | Should be added in production (HTTPS only) |

The cookie is read on protected requests by:
```gleam
request.get_header(req, "cookie")
|> cookie.parse(...)
|> list.key_find(pairs, "pie_safe_session")
```

---

## Frontend Session Handling

The Lustre SPA does not decode or inspect the JWT client-side. Instead, the home page calls `/api/auth/me` on every load to verify the session server-side.

### Home Page Init Sequence (`ui/src/pages/home.gleam`)

```
Browser navigates to /home
         │
         ▼
home.init() called by Lustre router
  model = Loading
  dispatch CheckSession effect
         │
         ▼
  GET /api/auth/me
         │
    ┌────┴────────────────┐
    │                     │
200 Ok(SessionData)    Error (401 or network)
    │                     │
    ▼                     ▼
model = Authenticated  modem.replace("/sign-in")
(email, role)          → redirect to sign-in
```

**Model variants:**
- `Loading` — initial state while the `/me` fetch is in-flight
- `Authenticated(email: String)` — session confirmed; email shown on screen
- `Unauthenticated` — transient state; a `modem.replace` redirect fires immediately

**Sign-out** — clicking the sign-out button dispatches `SignOut`, which redirects to `/sign-in`. The session cookie expires naturally (24h) or can be cleared server-side with a `POST /api/auth/sign-out` endpoint (not yet implemented; cookie expiry handles the case).

---

## File Map

| File | Role |
|---|---|
| `backend/src/backend/token.gleam` | `generate()` and `hash()` functions |
| `backend/src/backend/jwt.gleam` | `sign(claims, secret)` and `verify(token, secret)` |
| `backend/src/backend/auth.gleam` | HTTP handlers for all 4 auth endpoints + `AuthCtx` type |
| `backend/src/backend/config.gleam` | `jwt_secret: String` field loaded from `JWT_SECRET` env var |
| `backend/src/backend/registry_actor.gleam` | All registry DB operations including token storage |
| `backend/src/backend/family_db_actor.gleam` | `InsertMember` (for new family setup during registration) |
| `ui/src/pages/home.gleam` | Frontend session check via `/api/auth/me` |
| `ui/src/pages/sign_in.gleam` | Magic-link request form |
| `ui/src/pages/sign_up.gleam` | Registration form |

---

## Environment Variables for Auth

| Variable | Required | Description |
|---|---|---|
| `JWT_SECRET` | Yes | HS256 signing secret. Must be kept secret. Panics at startup if missing. |

In development, set this in `.envrc`:
```sh
export JWT_SECRET=dev-secret-change-me
```

In production, use a cryptographically random secret of at least 32 bytes.
