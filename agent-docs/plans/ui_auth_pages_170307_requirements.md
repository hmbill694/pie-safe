# Requirements: UI Auth Pages (Sign-Up, Sign-In, Home)

## Overview

Build three pages in the Lustre SPA (`ui/` package) to implement the auth flow entry points for Pie Safe. The existing `ui/src/ui.gleam` hello-world stub is replaced.

---

## Routing

- Add the `modem` Gleam package for real URL-based client-side routing.
- Routes:
  - `/sign-up` → Sign-Up page
  - `/sign-in` → Sign-In page
  - `/home` → Home page (protected)
- Unknown routes redirect to `/sign-in`.

---

## Sign-Up Page (`/sign-up`)

- **Fields:** First name, Last name, Family name, Email
- **Submit behaviour:** POST to `/api/auth/register` with JSON body `{ first_name, last_name, family_name, email }`
- **Success state:** Hide the form, show a "Check your email" confirmation message
- **Error state:** Show an inline error message below the form
- **Loading state:** Disable the submit button and show a spinner/loading indicator
- **Navigation:** Link to `/sign-in` ("Already have an account? Sign in")

---

## Sign-In Page (`/sign-in`)

- **Fields:** Email only
- **Submit behaviour:** POST to `/api/auth/magic-link` with JSON body `{ email }`
- **Success state:** Hide the form, show a "Check your email" confirmation message
- **Error state:** Show an inline error message below the form
- **Loading state:** Disable the submit button and show a spinner/loading indicator
- **Navigation:** Link to `/sign-up` ("Don't have an account? Sign up")

---

## Home Page (`/home`)

- Stubbed page — full feature implementation is future work.
- On load: read JWT from `localStorage` key `"pie_safe_token"`.
  - If no JWT found: redirect to `/sign-in`.
  - If JWT found: decode the payload (base64, no verification needed client-side) and display the user's email.
- Display: "Welcome to Pie Safe" heading + the email from the JWT payload.
- Sign-out button: clears `localStorage` and navigates to `/sign-in`.

---

## General / Technical

- **Styling:** Tailwind CSS (already wired up in the project). Clean, minimal design appropriate for a health-record app. Use a neutral colour palette (grays, with a muted blue/teal accent).
- **Form state:** Managed in the Lustre model — variants for `Idle`, `Loading`, `Success`, `Error(String)`.
- **API calls:** Use `lustre/effect` with the browser `fetch` API via Gleam FFI (or `lustre_http` if available/preferred by the planner).
- **File structure:**
  - `ui/src/ui.gleam` — entry point, app init, routing shell
  - `ui/src/pages/sign_up.gleam` — sign-up page view + update logic
  - `ui/src/pages/sign_in.gleam` — sign-in page view + update logic
  - `ui/src/pages/home.gleam` — home page view + update logic
- **No backend changes** — the API endpoints are assumed to exist (or will return errors gracefully during testing).
- The `modem` package must be added to `ui/gleam.toml` dependencies and `ui/manifest.toml`.
