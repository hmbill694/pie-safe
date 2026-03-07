## Implementation Plan: UI Auth Pages (Sign-Up, Sign-In, Home)

### Overview

This plan replaces the hello-world `ui/src/ui.gleam` stub with a full Lustre SPA featuring three pages (Sign-Up, Sign-In, Home), client-side URL routing via `modem`, and HTTP API calls via `lustre_http`. All work is confined to the `ui/` package — no backend changes.

---

### Step 1 — Add dependencies

- [ ] From the `ui/` directory, run `gleam add modem` to add `modem` (client-side URL routing) to `gleam.toml` and `manifest.toml`.
- [ ] From the `ui/` directory, run `gleam add lustre_http` to add `lustre_http` (HTTP effects) to `gleam.toml` and `manifest.toml`.
- [ ] Verify that `gleam.toml` `[dependencies]` now lists both `modem` and `lustre_http` with auto-resolved version constraints.

---

### Step 2 — Create the directory structure

- [ ] Create the directory `ui/src/pages/` (it does not exist yet).
- [ ] Confirm the three new files to be created are:
  - `ui/src/pages/sign_up.gleam`
  - `ui/src/pages/sign_in.gleam`
  - `ui/src/pages/home.gleam`
- [ ] The existing `ui/src/ui.gleam` will be entirely **replaced** (not extended).

---

### Step 3 — Create `ui/src/pages/sign_up.gleam`

This module owns all Sign-Up page state, messages, and view logic.

- [ ] Define a `FormState` type with four variants:
  - `Idle` — default, form ready for input
  - `Loading` — submission in progress
  - `Success` — email sent, show confirmation
  - `Error(String)` — show inline error message
- [ ] Define a `Model` record containing:
  - `first_name: String`
  - `last_name: String`
  - `family_name: String`
  - `email: String`
  - `state: FormState`
- [ ] Define a `Msg` type with variants:
  - `UpdateFirstName(String)`
  - `UpdateLastName(String)`
  - `UpdateFamilyName(String)`
  - `UpdateEmail(String)`
  - `Submit` — triggers the HTTP effect
  - `ApiResponse(Result(Nil, lustre_http.HttpError))` — receives the API result
- [ ] Implement `init() -> Model` returning a `Model` with all strings empty and `state` set to `Idle`.
- [ ] Implement `update(model: Model, msg: Msg) -> #(Model, Effect(Msg))`:
  - `UpdateFirstName`, `UpdateLastName`, `UpdateFamilyName`, `UpdateEmail` → update the relevant field, return `effect.none()`
  - `Submit` → set `state` to `Loading`, return a `lustre_http.post` effect:
    - URL: `"/api/auth/register"`
    - Body: a `gleam_json` object with fields `first_name`, `last_name`, `family_name`, `email`
    - Expect: `lustre_http.expect_anything(ApiResponse)`
  - `ApiResponse(Ok(_))` → set `state` to `Success`, return `effect.none()`
  - `ApiResponse(Error(err))` → set `state` to `Error(...)` with a human-readable message derived from the `HttpError` variant, return `effect.none()`
- [ ] Implement `view(model: Model) -> Element(Msg)`:
  - When `state == Success`: render a centered card with a "Check your email" heading and a short confirmation message; no form.
  - Otherwise: render a centered card containing:
    - A page heading ("Create your account" or similar)
    - Four labelled text inputs for first name, last name, family name, and email — each wired to their respective `Update*` message via `lustre/event.on_input`
    - A submit button wired to `Submit` via `lustre/event.on_click`; button is `disabled` and shows a loading indicator when `state == Loading`
    - An inline error paragraph (conditionally rendered) when `state == Error(msg)` — shown below the form in a muted red/rose colour
    - A navigation link: "Already have an account? Sign in" → `href="/sign-in"`
  - Styling: Tailwind CSS classes only. Use a neutral gray palette with a muted teal/blue accent (`teal-600` or `blue-600`) for the submit button.

---

### Step 4 — Create `ui/src/pages/sign_in.gleam`

This module owns all Sign-In page state, messages, and view logic.

- [ ] Define a `FormState` type — identical variants to Sign-Up: `Idle`, `Loading`, `Success`, `Error(String)`.
- [ ] Define a `Model` record containing:
  - `email: String`
  - `state: FormState`
- [ ] Define a `Msg` type with variants:
  - `UpdateEmail(String)`
  - `Submit`
  - `ApiResponse(Result(Nil, lustre_http.HttpError))`
- [ ] Implement `init() -> Model` returning empty email and `state = Idle`.
- [ ] Implement `update(model: Model, msg: Msg) -> #(Model, Effect(Msg))`:
  - `UpdateEmail` → update field, return `effect.none()`
  - `Submit` → set `state` to `Loading`, return a `lustre_http.post` effect:
    - URL: `"/api/auth/magic-link"`
    - Body: JSON object `{ email }`
    - Expect: `lustre_http.expect_anything(ApiResponse)`
  - `ApiResponse(Ok(_))` → `state = Success`, `effect.none()`
  - `ApiResponse(Error(err))` → `state = Error(...)`, `effect.none()`
- [ ] Implement `view(model: Model) -> Element(Msg)`:
  - `Success` state: centered card with "Check your email" confirmation.
  - Otherwise: centered card with:
    - Page heading ("Sign in to Pie Safe" or similar)
    - Single email input wired to `UpdateEmail`
    - Submit button wired to `Submit`; disabled + loading indicator when `Loading`
    - Inline error paragraph when `Error(msg)`
    - Navigation link: "Don't have an account? Sign up" → `href="/sign-up"`
  - Tailwind styling: same neutral/teal palette as Sign-Up.

---

### Step 5 — Create `ui/src/pages/home.gleam`

This module owns the Home page, including JWT reading and sign-out.

- [ ] Define a `Model` type:
  - A variant `Authenticated(email: String)` — JWT found and email decoded
  - A variant `Unauthenticated` — used only briefly before the redirect effect fires
- [ ] Define a `Msg` type with variants:
  - `GotToken(Result(String, Nil))` — receives the JWT string (or `Error(Nil)` if absent) from an effect
  - `SignOut`
- [ ] Create a **localStorage FFI module** at `ui/src/ffi/local_storage.gleam` (plus a companion `.ffi.mjs` file at `ui/src/ffi/local_storage.ffi.mjs`):
  - The `.ffi.mjs` file exports two JS functions:
    - `getItem(key)` → returns the value string or `null`
    - `removeItem(key)` → removes the key, returns `undefined`
  - The `.gleam` file wraps these as Gleam `@external` functions returning `Result(String, Nil)` and `Nil` respectively.
- [ ] Create a **JWT decode helper** inside `home.gleam` (or a shared `ui/src/jwt.gleam` module):
  - Implement a pure Gleam function `decode_email(token: String) -> Result(String, Nil)`:
    - Split the JWT string on `"."` to get three parts
    - Take the second part (payload), add padding (`=`) as needed, base64-decode it using `gleam_stdlib`'s `gleam/base` module
    - Parse the resulting string as JSON using `gleam_json` and extract the `"email"` field as a string
    - Return `Ok(email)` on success, `Error(Nil)` on any failure
- [ ] Implement `init() -> #(Model, Effect(Msg))`:
  - Start with `model = Unauthenticated`
  - Return a `lustre/effect.from` effect that calls the localStorage FFI `getItem("pie_safe_token")` and dispatches `GotToken(result)`
- [ ] Implement `update(model: Model, msg: Msg) -> #(Model, Effect(Msg))`:
  - `GotToken(Ok(token))`:
    - Attempt to `decode_email(token)`
    - On `Ok(email)`: transition to `Authenticated(email)`, `effect.none()`
    - On `Error(_)`: stay `Unauthenticated`, return `modem.replace("/sign-in", None, None)` to redirect
  - `GotToken(Error(_))`: stay `Unauthenticated`, return `modem.replace("/sign-in", None, None)`
  - `SignOut`: call localStorage FFI `removeItem("pie_safe_token")`, return `modem.replace("/sign-in", None, None)`
- [ ] Implement `view(model: Model) -> Element(Msg)`:
  - `Unauthenticated`: render an empty `html.div([], [])` (the redirect effect fires immediately; this state is transient)
  - `Authenticated(email)`: render a centered card with:
    - "Welcome to Pie Safe" heading
    - The user's email displayed beneath
    - A "Sign out" button wired to `SignOut`
  - Tailwind styling: same neutral palette; sign-out button in muted gray.

---

### Step 6 — Rewrite `ui/src/ui.gleam` (the app shell)

This file becomes the top-level Lustre application with routing.

- [ ] Remove the existing hello-world content entirely.
- [ ] Import: `lustre`, `lustre/effect`, `modem`, `gleam/uri`, `gleam/option`, and the three page modules.
- [ ] Define a `Route` type:
  - `SignUp`
  - `SignIn`
  - `Home`
- [ ] Define a top-level `Model` record containing:
  - `route: Route`
  - `sign_up: pages/sign_up.Model`
  - `sign_in: pages/sign_in.Model`
  - `home: pages/home.Model` (note: Home's init returns a tuple, so track just the model here)
- [ ] Define a top-level `Msg` type:
  - `OnRouteChange(Route)` — dispatched by `modem` on URL changes
  - `SignUpMsg(sign_up.Msg)` — wraps sign-up messages
  - `SignInMsg(sign_in.Msg)` — wraps sign-in messages
  - `HomeMsg(home.Msg)` — wraps home messages
- [ ] Implement a `parse_route(uri: Uri) -> Route` function:
  - `["sign-up"]` → `SignUp`
  - `["sign-in"]` → `SignIn`
  - `["home"]` → `Home`
  - `_` (anything else) → `SignIn` (default/unknown routes)
- [ ] Implement `init(_flags) -> #(Model, Effect(Msg))`:
  - Call `modem.initial_uri()` and parse the route with `parse_route`; default to `SignIn` on error
  - Initialise all three page sub-models: `sign_up.init()`, `sign_in.init()`, `home.init()`
  - Because `home.init()` returns `#(Model, Effect(Msg))`, unwrap and map the effect through `HomeMsg`
  - Return the composed `Model` and an `effect.batch([modem.init(on_url_change), home_effect])` so modem is set up and the home token-check fires if starting on `/home`
- [ ] Implement `on_url_change(uri: Uri) -> Msg`:
  - Calls `parse_route(uri)` and returns `OnRouteChange(route)`
- [ ] Implement `update(model: Model, msg: Msg) -> #(Model, Effect(Msg))`:
  - `OnRouteChange(route)`:
    - Update `model.route`
    - If the new route is `Home`: re-run `home.init()` (to re-trigger the token check) and map the effect; this ensures token check runs on every navigation to `/home`
    - Otherwise return `effect.none()`
  - `SignUpMsg(sub_msg)`: delegate to `sign_up.update(model.sign_up, sub_msg)`, update `model.sign_up`, map effect through `SignUpMsg`
  - `SignInMsg(sub_msg)`: delegate to `sign_in.update(model.sign_in, sub_msg)`, update `model.sign_in`, map effect through `SignInMsg`
  - `HomeMsg(sub_msg)`: delegate to `home.update(model.home, sub_msg)`, update `model.home`, map effect through `HomeMsg`
- [ ] Implement `view(model: Model) -> Element(Msg)`:
  - Pattern match on `model.route`:
    - `SignUp` → call `sign_up.view(model.sign_up)` and map through `SignUpMsg`
    - `SignIn` → call `sign_in.view(model.sign_in)` and map through `SignInMsg`
    - `Home` → call `home.view(model.home)` and map through `HomeMsg`
  - Wrap in a single `html.div` with a `"min-h-screen bg-gray-50"` class to provide the global background
- [ ] Update `main()` to use `lustre.application(init, update, view)` (not `lustre.simple`) since effects are needed, and start it on `"#app"` with `Nil` flags.

---

### Step 7 — Wire up `gleam_json` imports for JSON encoding

- [ ] In both `sign_up.gleam` and `sign_in.gleam`, import `gleam/json` to build the POST body.
- [ ] `gleam_json` is already present in the `manifest.toml` as a transitive dependency of `lustre`; confirm it is usable without a separate `gleam add gleam_json` (if not available directly, add it).

---

### Step 8 — Verify the build

- [ ] From the `ui/` directory, run `gleam build` and confirm zero compile errors.
- [ ] Fix any type mismatches or missing imports surfaced by the compiler.
- [ ] Optionally run `gleam run -m lustre/dev -- start` (or the project's equivalent dev command) and manually navigate to `/sign-up`, `/sign-in`, and `/home` in the browser to verify:
  - Routes render the correct page
  - Unknown routes redirect to `/sign-in`
  - `/home` with no localStorage token redirects to `/sign-in`
  - Forms render, inputs are interactive, and the loading state disables the submit button on click

---

### File Summary

| File | Action |
|---|---|
| `ui/gleam.toml` | Add `modem` and `lustre_http` dependencies |
| `ui/manifest.toml` | Auto-updated by `gleam add` |
| `ui/src/ui.gleam` | **Replace entirely** — new app shell with routing |
| `ui/src/pages/sign_up.gleam` | **New** — Sign-Up page |
| `ui/src/pages/sign_in.gleam` — | **New** — Sign-In page |
| `ui/src/pages/home.gleam` | **New** — Home page with JWT read + auth guard |
| `ui/src/ffi/local_storage.gleam` | **New** — Gleam FFI bindings for localStorage |
| `ui/src/ffi/local_storage.ffi.mjs` | **New** — JS side of localStorage FFI |
