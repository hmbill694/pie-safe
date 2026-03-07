# Requirements: Homepage & Member Detail (Frontend-Only)

## Scope
Frontend-only work. No backend API calls. All data is mock/hardcoded in-memory state. Saves update in-memory state only (not persisted across refreshes).

---

## Navbar (authenticated pages only)
- Appears on `/home` and all `/members/*` pages
- Does **not** appear on `/sign-in` or `/sign-up`
- Contains: app name/logo ("Pie Safe"), and a sign-out button
- Consistent with existing teal/gray colour palette

---

## Homepage (`/home`)
- **Navbar** at the top
- **Search bar** — text input that filters member cards client-side by name (first or last)
- **"Add Member" button** — navigates to the new member page (`/members/new`)
- **Responsive member grid/list:**
  - Desktop: multi-column grid (e.g. 3 columns)
  - Tablet: 2 columns
  - Mobile: single-column list
  - Uses Tailwind responsive classes (`grid`, `sm:grid-cols-2`, `lg:grid-cols-3`)
- **Member cards** (one per mock family member):
  - Coloured circle avatar with the member's initials
  - First name + last name
  - Date of birth
  - Role (admin / member) and managed flag (child/dependent indicator)
  - Clicking the card navigates to `/members/:id`
- **Mock data**: 3–5 hardcoded family members covering different combinations (admin, member, managed/unmanaged, various ages)

---

## Member Detail Page (`/members/:id` and `/members/new`)
- **Navbar** at the top
- Loads the member from in-memory mock state by ID; `/members/new` shows a blank form
- **Core member fields** (editable):
  - First name, last name, email, date of birth, role, is_managed (child toggle)
- **Related health data sections** (each as a collapsible/tabbed section with add/edit/delete in-memory):
  - Allergies
  - Medications
  - Immunizations
  - Insurance
  - Providers
  - Emergency Contacts
  - Documents
- Changes update the in-memory Lustre model only (no API calls, no persistence)
- A "Save" button on the core fields form that updates the in-memory state

---

## Routing
- Add new `Route` variants: `MemberDetail(id: Int)` and `NewMember`
- Update the `modem` URL router to match `/members/:id` and `/members/new`
- All navigation (card click, "Add Member" button) uses `modem.push` for SPA routing

---

## Tech Constraints
- Gleam + Lustre (Elm architecture)
- Tailwind CSS v4
- No new dependencies
