# Implementation Plan: Homepage & Member Detail

## Overview

Five discrete work items in dependency order:
1. Mock data module (no dependencies)
2. Navbar component (no dependencies)
3. Homepage rewrite (depends on #1, #2)
4. Member detail page (depends on #1, #2)
5. Root routing updates in `ui.gleam` (depends on #3, #4)

---

## Step-by-step checklist

### Step 1 — Create `ui/src/data/mock_members.gleam`

- [ ] Create the new directory `ui/src/data/` and file `ui/src/data/mock_members.gleam`.

- [ ] Define the `Role` type:
  ```
  type Role { Admin | Member }
  ```

- [ ] Define the `Member` type with fields matching the members table:
  ```
  id: Int, email: String, first_name: String, last_name: String,
  date_of_birth: String (ISO-8601 "YYYY-MM-DD"), role: Role, is_managed: Bool
  ```

- [ ] Define all related health data types (each as a plain Gleam record with an `id: Int` field plus domain fields):
  - `Allergy` — `id`, `name: String`, `severity: String`, `notes: String`
  - `Medication` — `id`, `name: String`, `dosage: String`, `frequency: String`, `prescribing_provider: String`
  - `Immunization` — `id`, `vaccine_name: String`, `date_administered: String`, `administered_by: String`
  - `InsurancePolicy` — `id`, `provider_name: String`, `policy_number: String`, `group_number: String`, `plan_type: String`
  - `Provider` — `id`, `name: String`, `specialty: String`, `phone: String`, `address: String`
  - `EmergencyContact` — `id`, `name: String`, `relationship: String`, `phone: String`
  - `Document` — `id`, `name: String`, `document_type: String`, `notes: String`

- [ ] Define `MemberWithData`:
  ```
  MemberWithData(
    member: Member,
    allergies: List(Allergy),
    medications: List(Medication),
    immunizations: List(Immunization),
    insurance_policies: List(InsurancePolicy),
    providers: List(Provider),
    emergency_contacts: List(EmergencyContact),
    documents: List(Document),
  )
  ```

- [ ] Define 4 hardcoded mock `MemberWithData` values in a private `let` or inline in `all_members()`:
  - **Member 1** (id=1): Admin, not managed — the primary account holder, adult, has allergies + a provider
  - **Member 2** (id=2): Member, not managed — spouse/partner, adult, has insurance + medications
  - **Member 3** (id=3): Member, is_managed=True — child, DOB ~2016, minimal data
  - **Member 4** (id=4): Member, is_managed=True — second child, DOB ~2019, no health data

- [ ] Define two public helper functions:
  ```
  pub fn all_members() -> List(MemberWithData)
  pub fn get_member_by_id(id: Int) -> Option(MemberWithData)
  ```
  `get_member_by_id` uses `list.find` from `gleam/list` and wraps the result in `option.from_result`.

  **Imports needed:** `gleam/list`, `gleam/option.{type Option, None, Some}`

---

### Step 2 — Create `ui/src/components/navbar.gleam`

- [ ] Create the new directory `ui/src/components/` and file `ui/src/components/navbar.gleam`.

- [ ] Define a single public function with a generic message type parameter:
  ```
  pub fn navbar(on_sign_out: msg) -> Element(msg)
  ```
  This keeps the navbar reusable across home and member_detail without coupling to a specific `Msg` type.

- [ ] The navbar renders an `html.nav` with:
  - Tailwind classes: `"sticky top-0 z-10 bg-white border-b border-gray-200 shadow-sm"`
  - Inner `html.div` with `"max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between"`

- [ ] Left side: brand name element
  - `html.span` with `"text-xl font-bold text-teal-600"` containing the text `"Pie Safe"`

- [ ] Right side: sign-out button
  - `html.button` with class `"bg-gray-200 hover:bg-gray-300 text-gray-700 font-semibold py-2 px-4 rounded-lg transition-colors"` (mirrors the existing sign-out button style from `home.gleam`)
  - `event.on_click(on_sign_out)` — passes through the caller-provided message
  - Text: `"Sign Out"`

- [ ] Imports needed: `lustre/attribute`, `lustre/element.{type Element}`, `lustre/element/html`, `lustre/event`

---

### Step 3 — Rewrite `ui/src/pages/home.gleam`

- [ ] **Replace the existing `Model` type** (currently a union) with a record:
  ```
  pub type Model {
    Model(
      auth_state: AuthState,
      members: List(MemberWithData),
      search_query: String,
    )
  }
  ```

- [ ] **Define `AuthState`** (replaces the old union):
  ```
  pub type AuthState { Loading | Authenticated(email: String) | Unauthenticated }
  ```

- [ ] **Update `Msg`**:
  ```
  pub type Msg {
    GotSession(Result(SessionData, lustre_http.HttpError))
    SearchChanged(String)
    SignOut
    NavigateTo(String)
  }
  ```
  Keep `SessionData` as-is.

- [ ] **Update `init/0`**:
  ```
  pub fn init() -> #(Model, Effect(Msg)) {
    #(
      Model(auth_state: Loading, members: mock_members.all_members(), search_query: ""),
      check_session_effect(),
    )
  }
  ```

- [ ] **Update `update/2`**:
  - `GotSession(Ok(data))` → `Model(..model, auth_state: Authenticated(email: data.email))`
  - `GotSession(Error(_))` → `Model(..model, auth_state: Unauthenticated)` + `modem.replace("/sign-in", None, None)`
  - `SearchChanged(q)` → `Model(..model, search_query: q)`, `effect.none()`
  - `SignOut` → `Model(..model, auth_state: Unauthenticated)` + `modem.replace("/sign-in", None, None)`
  - `NavigateTo(path)` → `#(model, modem.push(path, None, None))`

- [ ] **Rewrite `view/1`**:
  - Pattern-match on `model.auth_state`:
    - `Loading` → full-screen centered spinner/text (same pattern as old `Loading`)
    - `Unauthenticated` → empty `html.div([], [])`
    - `Authenticated(_)` → call the main page view (private helper)

- [ ] **Add private `authenticated_view(model: Model) -> Element(Msg)`**:
  - Root: `html.div([attribute.class("min-h-screen bg-gray-50")], [...])`
  - First child: `navbar.navbar(SignOut)`
  - Second child: the page content wrapper `html.main([attribute.class("max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8")], [search_and_add_bar(model), member_grid(model)])`

- [ ] **Add private `search_and_add_bar(model: Model) -> Element(Msg)`**:
  - `html.div([attribute.class("flex items-center gap-4 mb-8")], [search_input, add_member_button])`
  - Search input: `html.input` with `attribute.type_("search")`, `attribute.value(model.search_query)`, `event.on_input(SearchChanged)`, class `"flex-1 border border-gray-300 rounded-lg px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-transparent"`, `attribute.placeholder("Search members...")`
  - Add Member button: `html.button` with `event.on_click(NavigateTo("/members/new"))` and class `"bg-teal-600 hover:bg-teal-700 text-white font-semibold py-2 px-4 rounded-lg transition-colors"`, text `"Add Member"`

- [ ] **Add private `member_grid(model: Model) -> Element(Msg)`**:
  - Filter `model.members` by `search_query`: for each `MemberWithData`, check if `string.contains(string.lowercase(m.member.first_name), string.lowercase(model.search_query))` OR same for `last_name`. Use `list.filter` from `gleam/list` and `gleam/string`.
  - Render: `html.div([attribute.class("grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4")], list.map(filtered, member_card))`

- [ ] **Add private `member_card(mwd: MemberWithData) -> Element(Msg)`**:
  - Outer: `html.div` with `event.on_click(NavigateTo("/members/" <> int.to_string(mwd.member.id)))` and class `"bg-white rounded-lg shadow-sm border border-gray-200 p-5 flex items-center gap-4 cursor-pointer hover:shadow-md hover:border-teal-200 transition-all"`
  - Avatar circle: `html.div([attribute.class("flex-shrink-0 w-12 h-12 rounded-full flex items-center justify-center text-white font-bold text-lg " <> avatar_colour(mwd.member.first_name))], [element.text(initials(mwd.member))])`
  - Info block `html.div([attribute.class("flex-1 min-w-0")], [name_line, dob_line, badge_line])`
  - Name: `html.p([attribute.class("font-semibold text-gray-900 truncate")], [element.text(mwd.member.first_name <> " " <> mwd.member.last_name)])`
  - DOB: `html.p([attribute.class("text-sm text-gray-500")], [element.text("DOB: " <> mwd.member.date_of_birth)])`
  - Badges row: `html.div([attribute.class("flex items-center gap-2 mt-1")], [role_badge, managed_badge_if_applicable])`
    - Role badge (Admin): `"text-xs font-medium px-2 py-0.5 rounded-full bg-teal-100 text-teal-700"`; Member: `"text-xs font-medium px-2 py-0.5 rounded-full bg-gray-100 text-gray-600"`
    - Managed badge (only when `is_managed = True`): `"text-xs font-medium px-2 py-0.5 rounded-full bg-amber-100 text-amber-700"` with text `"Child"`

- [ ] **Add private `initials(member: Member) -> String`**:
  - Take first grapheme of `first_name` + first grapheme of `last_name`, uppercase both. Use `string.first` and `string.uppercase` from `gleam/string`.

- [ ] **Add private `avatar_colour(first_name: String) -> String`**:
  - Get the char code of the first character: use `string.to_utf_codepoints` on `string.slice(first_name, 0, 1)`, take `list.first`, then `string.utf_codepoint_to_int`. If empty, default to 0.
  - Map `int.remainder(code, 8)` (or `code % 8`) to a list of 8 Tailwind bg-colour classes using a `case` expression with literal strings per branch:
    - 0: `"bg-teal-500"`, 1: `"bg-indigo-500"`, 2: `"bg-amber-500"`, 3: `"bg-rose-500"`, 4: `"bg-violet-500"`, 5: `"bg-emerald-500"`, 6: `"bg-sky-500"`, 7: `"bg-orange-500"`

- [ ] **Imports needed in home.gleam**: `data/mock_members.{type MemberWithData}`, `components/navbar`, `gleam/list`, `gleam/string`, `gleam/int`, `modem`, plus existing imports. Remove unused imports.

---

### Step 4 — Create `ui/src/pages/member_detail.gleam`

- [ ] **Define `Section` type**:
  ```
  pub type Section {
    CoreInfo | Allergies | Medications | Immunizations
    | Insurance | Providers | EmergencyContacts | Documents
  }
  ```

- [ ] **Define `EditTarget` type** to track what is being edited inline:
  ```
  pub type EditTarget {
    EditingAllergy(id: Int)
    EditingMedication(id: Int)
    EditingImmunization(id: Int)
    EditingInsurance(id: Int)
    EditingProvider(id: Int)
    EditingEmergencyContact(id: Int)
    EditingDocument(id: Int)
    AddingAllergy
    AddingMedication
    AddingImmunization
    AddingInsurance
    AddingProvider
    AddingEmergencyContact
    AddingDocument
  }
  ```

- [ ] **Define `Model`**:
  ```
  pub type Model {
    Model(
      member: MemberWithData,
      is_new: Bool,
      active_section: Section,
      editing_item: Option(EditTarget),
      draft_first_name: String,
      draft_last_name: String,
      draft_email: String,
      draft_dob: String,
      draft_role: Role,
      draft_is_managed: Bool,
      draft_allergy: Allergy,
      draft_medication: Medication,
      draft_immunization: Immunization,
      draft_insurance: InsurancePolicy,
      draft_provider: Provider,
      draft_emergency_contact: EmergencyContact,
      draft_document: Document,
      next_id: Int,
    )
  }
  ```

- [ ] **Define `Msg` variants**:
  - Core field updates: `UpdateFirstName(String)`, `UpdateLastName(String)`, `UpdateEmail(String)`, `UpdateDob(String)`, `UpdateRole(Role)`, `ToggleManaged`
  - Core save: `SaveCoreInfo`
  - Section tab: `SetSection(Section)`
  - Navigation: `NavigateTo(String)`
  - Per health section CRUD (repeat for Allergy, Medication, Immunization, InsurancePolicy, Provider, EmergencyContact, Document):
    - `StartAddAllergy`, `StartEditAllergy(Int)`, `DeleteAllergy(Int)`, `SaveAllergy`, `CancelEdit`
    - `UpdateAllergyName(String)`, `UpdateAllergySeverity(String)`, `UpdateAllergyNotes(String)`
    - (repeat field-update and save/cancel pattern for all 7 types)

- [ ] **Define `init(maybe_id: Option(Int)) -> #(Model, Effect(Msg))`**:
  - If `Some(id)`: call `mock_members.get_member_by_id(id)`. If `Some(mwd)`, populate drafts from member fields, `is_new: False`. If `None`, create blank with `is_new: True`.
  - If `None`: create blank model with `is_new: True` — blank `MemberWithData` with all empty lists.
  - Both paths return `effect.none()`.
  - `next_id` starts at 100.

- [ ] **Define `update(model, msg) -> #(Model, Effect(Msg))`**:
  - Core field updates: `Model(..model, draft_first_name: v)` etc.
  - `SaveCoreInfo`: rebuild `Member` record from draft fields, then rebuild `MemberWithData`, update `model.member`
  - `SetSection(s)`: `Model(..model, active_section: s, editing_item: None)`
  - `NavigateTo(path)`: `#(model, modem.push(path, None, None))`
  - `StartAddX`: set `editing_item: Some(AddingX)`, reset draft to empty
  - `StartEditX(id)`: find item by id, populate draft, set `editing_item: Some(EditingX(id))`
  - `SaveX` (Adding): append draft (with `next_id`) to list, increment `next_id`, clear `editing_item`
  - `SaveX` (Editing id): replace matching item in list, clear `editing_item`
  - `DeleteX(id)`: filter out item from list
  - `CancelEdit`: `Model(..model, editing_item: None)`

- [ ] **Define `view(model: Model) -> Element(Msg)`**:
  - Root: `html.div([attribute.class("min-h-screen bg-gray-50")], [navbar, page_content])`
  - Navbar: `navbar.navbar(NavigateTo("/home"))` (navigates back to home; acceptable for frontend-only)
  - Page heading and back button in a header div
  - Core info card (always visible)
  - Section tabs
  - Section content area (pattern-match on `active_section`)

- [ ] **Core info section**:
  - Card: `html.div([attribute.class("bg-white rounded-lg shadow-sm border border-gray-200 p-6 mb-6")], [...])`
  - Labeled inputs for all 6 core fields (same `labeled_input` helper pattern from sign_up.gleam)
  - Role: `html.select` with "Admin"/"Member" options
  - is_managed: checkbox `html.input([attribute.type_("checkbox")])`
  - "Save" button: teal style, `event.on_click(SaveCoreInfo)`

- [ ] **Section tab bar**:
  - `html.div([attribute.class("flex overflow-x-auto gap-1 mb-6 border-b border-gray-200")], tab_buttons)`
  - Active tab: `"border-b-2 border-teal-600 text-teal-600 font-medium px-4 py-2 text-sm whitespace-nowrap"`
  - Inactive tab: `"text-gray-600 hover:text-gray-900 px-4 py-2 text-sm whitespace-nowrap transition-colors"`

- [ ] **Section content panels** (one per section type):
  - Wrapper: `html.div([attribute.class("bg-white rounded-lg shadow-sm border border-gray-200 p-6")], [header, items, add_button])`
  - Item rows: flex row with details left, edit/delete buttons right
  - Edit/Add inline form: labeled inputs + Save (teal) + Cancel (gray) buttons
  - "Add [Type]" button shown when not currently adding; form shown when `editing_item == Some(AddingX)`

- [ ] **Nested record mutation pattern**:
  ```
  let updated_member = MemberWithData(..model.member, allergies: new_allergies)
  Model(..model, member: updated_member, editing_item: None)
  ```

- [ ] **Imports needed**: `data/mock_members.{...all types}`, `components/navbar`, `gleam/list`, `gleam/option`, `gleam/int`, `lustre/attribute`, `lustre/element`, `lustre/element/html`, `lustre/event`, `lustre/effect`, `modem`

---

### Step 5 — Update `ui/src/ui.gleam` (routing)

- [ ] **Add imports**: `pages/member_detail`, `gleam/int`

- [ ] **Add new `Route` variants**:
  ```
  MemberDetail(id: Int)
  NewMember
  ```

- [ ] **Update `parse_route/1`** — add before the catch-all:
  ```gleam
  ["members", "new"] -> NewMember
  ["members", id_str] ->
    case int.parse(id_str) {
      Ok(id) -> MemberDetail(id)
      Error(_) -> SignIn
    }
  ```
  `"new"` must appear before the general `id_str` binding.

- [ ] **Update root `Model`** — add `member_detail: member_detail.Model` field.

- [ ] **Update root `Msg`** — add `MemberDetailMsg(member_detail.Msg)`.

- [ ] **Update `init/1`** — initialise `member_detail.init(None)`, batch effect with `effect.map(_, MemberDetailMsg)`.

- [ ] **Update `update/2`**:
  - `OnRouteChange(MemberDetail(id))` → call `member_detail.init(Some(id))`, update model, map effect
  - `OnRouteChange(NewMember)` → call `member_detail.init(None)`, update model, map effect
  - `MemberDetailMsg(sub_msg)` → delegate to `member_detail.update`, update model, map effect

- [ ] **Update `view/1`**:
  ```gleam
  MemberDetail(_) -> element.map(member_detail.view(model.member_detail), MemberDetailMsg)
  NewMember -> element.map(member_detail.view(model.member_detail), MemberDetailMsg)
  ```

---

## Notes on tricky parts

### Parsing `:id` from URL segments
`int.parse(str) -> Result(Int, Nil)`. The `"new"` literal arm must appear before the general `id_str` binding in the case expression. Fallback on `Error(_)` routes to `SignIn`.

### Avatar colour derivation
All 8 Tailwind bg colour classes must appear as literal strings in source (not dynamically constructed) so Tailwind's scanner includes them. Use a `case` expression with one literal string per branch: `"bg-teal-500"`, `"bg-indigo-500"`, `"bg-amber-500"`, `"bg-rose-500"`, `"bg-violet-500"`, `"bg-emerald-500"`, `"bg-sky-500"`, `"bg-orange-500"`.

### modem.push vs event.on_click
`modem.push/3` returns `Effect(msg)`. Use `NavigateTo(String)` msg dispatched from click handlers, handled in `update` by returning `modem.push(path, None, None)`.

### Health item inline form state
One draft record per health data type in the model. Starting to edit populates the draft; saving commits it; cancelling clears `editing_item` only.

### MemberWithData mutation
Rebuild records from the inside out using Gleam's record update syntax (`..model.member`).

### Navbar on member_detail
Uses `NavigateTo("/home")` as the sign-out action — acceptable for frontend-only scope. Real sign-out will be added when backend integration lands.
