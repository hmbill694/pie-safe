# Implementation Plan: End-to-End Authentication Flow (Final)

## Enforced Constraints

1. **No hand-rolled JSON strings** — all JSON is built with `gleam_json` (`json.object`, `json.string`, `json.int`, `json.bool`, `json.to_string`).
2. **No inline SQL strings** — all DB operations use parrot-generated functions from `registry/src/registry/sql.gleam` and `backend/src/backend/sql.gleam`. No new parrot runs needed.
3. **JWT header and payload** — both constructed with `gleam_json`, not string concatenation.
4. **No custom base64url helpers** — use `bit_array.base64_url_encode/2` and `bit_array.base64_url_decode/1` from stdlib directly.
5. **No custom UUID generation** — use `youid/uuid.v4_string()`.
6. **No custom cookie parsing** — use `gleam/http/cookie.parse/1` from the already-present `gleam_http` dep.
7. **Timing-safe JWT signature comparison** — use `crypto.secure_compare/2` on `BitArray` values.

---

## Phase 0 — Prerequisites (Shell Commands)

- [ ] **0.1** Run `gleam add gleam_json` from the `backend/` directory.
- [ ] **0.2** Run `gleam add youid` from the `backend/` directory.

---

## Phase 1 — Environment Variables

- [ ] **1.1** In `.envrc`, append: `export JWT_SECRET=dev-secret-change-me`
- [ ] **1.2** In `.envrc.sample`, append: `export JWT_SECRET=`

---

## Phase 2 — Config (`backend/src/backend/config.gleam`)

- [ ] **2.1** Add `jwt_secret: String` to the `Config` record type.
- [ ] **2.2** Load `JWT_SECRET` via `envoy.get` with `panic as "Missing required environment variable: JWT_SECRET"`.
- [ ] **2.3** Add `jwt_secret:` to the `Config(...)` constructor call.

---

## Phase 3 — New File: `backend/src/backend/token.gleam`

Imports: `gleam/bit_array`, `gleam/crypto`, `gleam/string`.

- [ ] **3.1** `pub fn generate() -> String`: `crypto.strong_random_bytes(32) |> bit_array.base16_encode |> string.lowercase` → 64-char lowercase hex.
- [ ] **3.2** `pub fn hash(raw: String) -> String`: `bit_array.from_string(raw) |> crypto.hash(crypto.Sha256, _) |> bit_array.base16_encode |> string.lowercase`.

---

## Phase 4 — New File: `backend/src/backend/jwt.gleam`

Imports: `gleam/bit_array`, `gleam/crypto`, `gleam/string`, `gleam/result`, `gleam/int`, `gleam/json`, `gleam/dynamic/decode`.

- [ ] **4.1** Erlang FFI: `type TimeUnit { Second }` + `@external(erlang, "erlang", "system_time") fn system_time_seconds(unit: TimeUnit) -> Int`

- [ ] **4.2** `pub type Claims { Claims(family_id: String, account_id: Int, email: String, role: String, exp: Int) }`

- [ ] **4.3** `pub fn sign(claims: Claims, secret: String) -> String`:
  - Build header JSON with `gleam_json`: `json.object([#("alg", json.string("HS256")), #("typ", json.string("JWT"))]) |> json.to_string`
  - Build payload JSON with `gleam_json`: `json.object([#("family_id",...), #("account_id",...), #("email",...), #("role",...), #("exp",...) ]) |> json.to_string`
  - Encode both with stdlib: `bit_array.base64_url_encode(bit_array.from_string(json), False)`
  - Sign input `encoded_header <> "." <> encoded_payload` with `crypto.hmac(..., crypto.Sha256, ...)`
  - Encode signature with `bit_array.base64_url_encode(sig_bits, False)`
  - Return `signing_input <> "." <> encoded_sig`

- [ ] **4.4** `pub fn verify(token: String, secret: String) -> Result(Claims, String)`:
  - Split on `"."` → 3 parts or `Error("invalid token format")`
  - Re-compute HMAC over `part0 <> "." <> part1`
  - Decode `part2` with `bit_array.base64_url_decode` → `Error("invalid signature encoding")`
  - **Timing-safe compare**: `crypto.secure_compare(computed_bits, provided_bits)` → `Error("invalid signature")` if `False`
  - Decode `part1` with `bit_array.base64_url_decode` → `bit_array.to_string` → `Error` on failure
  - Parse payload JSON with `gleam_json` `decode.field` decoder → `Error("invalid payload json")`
  - Check `exp > system_time_seconds(Second)` → `Error("token expired")`
  - Return `Ok(Claims(...))`

---

## Phase 5 — Registry Actor: New Messages (`backend/src/backend/registry_actor.gleam`)

- [ ] **5.1** Add 5 new `Message` variants:
  - `GetAccount(reply_to: Subject(Result(Option(registry_sql.GetAccount), String)), id: Int)`
  - `InsertRegistryAuthToken(reply_to:, account_id:, token_hash:, token_type:, expires_at:, used_at: Option(String), created_at:)`
  - `GetRegistryAuthTokenByHash(reply_to: Subject(Result(Option(registry_sql.GetRegistryAuthTokenByHash), String)), token_hash:)`
  - `MarkRegistryAuthTokenUsed(reply_to:, used_at:, id: Int)`
  - `UpdateAccountLastLogin(reply_to:, last_login_at:, id: Int)`

- [ ] **5.2** Add 5 corresponding `handle_message` branches, each calling the matching parrot-generated `registry_sql.*` function via `db.exec_query` or `db.exec_command`. No raw SQL.

---

## Phase 6 — New File: `backend/src/backend/auth.gleam`

**Imports:** `backend/config`, `backend/family_db_actor`, `backend/family_db_supervisor`, `backend/jwt`, `backend/registry_actor`, `backend/sql as family_sql`, `backend/token`, `gleam/bit_array`, `gleam/bytes_tree`, `gleam/crypto`, `gleam/dynamic/decode`, `gleam/http/cookie`, `gleam/http/request`, `gleam/http/response`, `gleam/int`, `gleam/io`, `gleam/json`, `gleam/list`, `gleam/option`, `gleam/erlang/process`, `gleam/result`, `gleam/string`, `gleam/time/calendar`, `gleam/time/timestamp`, `mist`, `registry/sql as registry_sql`, `youid/uuid`

### AuthCtx

- [ ] **6.1** `pub type AuthCtx { AuthCtx(cfg: config.Config, registry_name: process.Name(registry_actor.Message), supervisor_name: process.Name(family_db_supervisor.Message)) }`

### Erlang FFI

- [ ] **6.2** Same `TimeUnit`/`system_time_seconds` FFI as `jwt.gleam`.

### Private Helpers

- [ ] **6.3** `fn now_iso()`: `timestamp.system_time() |> timestamp.to_rfc3339(calendar.utc_offset)`
- [ ] **6.4** `fn now_plus_15min_iso()`: `timestamp.from_unix_seconds(system_time_seconds(Second) + 900) |> timestamp.to_rfc3339(calendar.utc_offset)`
- [ ] **6.5** `fn json_response(status, body)`: set content-type + mist body
- [ ] **6.6** `fn json_ok()`: `json.object([#("ok", json.bool(True))]) |> json.to_string |> json_response(200, _)`
- [ ] **6.7** `fn json_error(status, msg)`: `json.object([#("error", json.string(msg))]) |> json.to_string |> json_response(status, _)`
- [ ] **6.8** `fn read_body_string(req)`: `mist.read_body(req, 1_000_000)` → `bit_array.to_string`
- [ ] **6.9** `fn generate_and_store_token(account_id, ctx)`: generate → hash → insert via `registry_actor.InsertRegistryAuthToken` → return `Ok(raw_token)`
- [ ] **6.10** `fn log_magic_link(raw_token, port)`: `io.println("[magic-link] http://localhost:<port>/api/auth/verify?token=<token>")`

### handle_register

- [ ] **6.11** Read body → parse JSON (`first_name`, `last_name`, `family_name`, `email`) with `gleam_json` decoder
- [ ] **6.12** Check email uniqueness via `registry_actor.GetAccountByEmail` → 409 if found
- [ ] **6.13** `family_id = uuid.v4_string()`, `db_path = "data/" <> family_id <> ".db"`, `now = now_iso()`
- [ ] **6.14** `registry_actor.InsertFamily` → `registry_actor.InsertAccount` → `registry_actor.GetAccountByEmail` (to get `account_id`)
- [ ] **6.15** `family_db_supervisor.GetOrStart` → `family_db_actor.Exec(family_sql.insert_member(...))` (parrot-generated)
- [ ] **6.16** `generate_and_store_token` → `log_magic_link` → `json_ok()`

### handle_magic_link

- [ ] **6.17** Read body → parse `{ email }` → `registry_actor.GetAccountByEmail` (404 if missing) → `generate_and_store_token` → `log_magic_link` → `json_ok()`

### handle_verify

- [ ] **6.18** Extract `?token=` from `req.query` (split `"&"`, find `"token="` key with `string.split_once`)
- [ ] **6.19** `token.hash(raw)` → `registry_actor.GetRegistryAuthTokenByHash` → validate unused + not expired
- [ ] **6.20** `registry_actor.MarkRegistryAuthTokenUsed` → `registry_actor.GetAccount` → `registry_actor.UpdateAccountLastLogin`
- [ ] **6.21** `jwt.sign(Claims(...), ctx.cfg.jwt_secret)` → set `Set-Cookie: pie_safe_session=<jwt>; HttpOnly; Path=/; SameSite=Lax` → redirect 302 to `/home`

### handle_me

- [ ] **6.22** `request.get_header(req, "cookie")` → `cookie.parse(...)` → `list.key_find(pairs, "pie_safe_session")` → 401 if missing
- [ ] **6.23** `jwt.verify(token, ctx.cfg.jwt_secret)` → 401 on failure
- [ ] **6.24** `json.object([#("email", ...), #("role", ...)]) |> json.to_string` → `json_response(200, body)`

---

## Phase 7 — Wire Routes (`backend/src/backend.gleam`)

- [ ] **7.1** Add `import backend/auth` and `import gleam/http`
- [ ] **7.2** `let ctx = auth.AuthCtx(cfg:, registry_name:, supervisor_name:)` after actor names are created
- [ ] **7.3** Add 4 route branches before the SPA fallback, each with method guard (`http.Post`/`http.Get`), falling back to existing `not_found` for wrong methods:
  - `["api", "auth", "register"]` → `auth.handle_register(req, ctx)`
  - `["api", "auth", "magic-link"]` → `auth.handle_magic_link(req, ctx)`
  - `["api", "auth", "verify"]` → `auth.handle_verify(req, ctx)`
  - `["api", "auth", "me"]` → `auth.handle_me(req, ctx)`

---

## Phase 8 — Frontend (`ui/src/pages/home.gleam`)

- [ ] **8.1** Remove unused imports; add `lustre_http`
- [ ] **8.2** `Model`: `Loading | Authenticated(email: String) | Unauthenticated`
- [ ] **8.3** Private `type SessionData { SessionData(email: String, role: String) }`
- [ ] **8.4** `Msg`: `GotSession(Result(SessionData, lustre_http.HttpError)) | SignOut`
- [ ] **8.5** `init()` → `#(Loading, check_session_effect())`
- [ ] **8.6** `check_session_effect()`: `decode.field` decoder for `SessionData` → `lustre_http.get("/api/auth/me", lustre_http.expect_json(decoder, GotSession))`
- [ ] **8.7** `update()`: `GotSession(Ok(data))` → `Authenticated`; `GotSession(Error(_))` / `SignOut` → `Unauthenticated` + `modem.replace("/sign-in", None, None)`
- [ ] **8.8** `view()`: add `Loading ->` branch; keep `Authenticated` and `Unauthenticated` branches unchanged
- [ ] **8.9** Remove unused `decode_email` function

---

## Phase 9 — Verify

- [ ] **9.1** Confirm `ui.gleam` calls `home.init()` on `OnRouteChange(Home)` — no changes needed.

---

## Implementation Order

1. Phase 0 — deps (`gleam add gleam_json youid`)
2. Phase 1 — env vars
3. Phase 3 — `token.gleam`
4. Phase 4 — `jwt.gleam`
5. Phase 2 — `config.gleam`
6. Phase 5 — `registry_actor.gleam`
7. Phase 6 — `auth.gleam`
8. Phase 7 — `backend.gleam` routing
9. Phase 8 — `home.gleam` frontend
10. Phase 9 — read-only verification
