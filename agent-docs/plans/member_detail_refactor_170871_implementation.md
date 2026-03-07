# Implementation Plan: Refactor `member_detail.gleam` into Sub-modules

## Overview

Split the 1709-line monolithic `member_detail.gleam` into 10 focused files inside a new `ui/src/pages/member_detail/` directory. `member_detail.gleam` becomes a thin orchestrator; `ui.gleam` is **never touched**.

---

## Step 0 — Create the directory

- [ ] Create the directory `ui/src/pages/member_detail/`

---

## Step 1 — Create `ui/src/pages/member_detail/types.gleam`

**Purpose:** Single source of truth for all shared types and blank-value helpers.

**Imports:**
```
import data/mock_members.{
  type Allergy, type Document, type EmergencyContact, type Immunization,
  type InsurancePolicy, type Medication, type MemberWithData, type Provider,
  type Role,
  Allergy, Document, EmergencyContact, Immunization, InsurancePolicy,
  Medication, MemberWithData, Provider,
}
import gleam/option.{type Option, None, Some}
```

**Types (all pub):**
- `Section`: CoreInfo | Allergies | Medications | Immunizations | Insurance | Providers | EmergencyContacts | Documents
- `EditTarget`: EditingAllergy(id: Int) | EditingMedication(id: Int) | EditingImmunization(id: Int) | EditingInsurance(id: Int) | EditingProvider(id: Int) | EditingEmergencyContact(id: Int) | EditingDocument(id: Int) | AddingAllergy | AddingMedication | AddingImmunization | AddingInsurance | AddingProvider | AddingEmergencyContact | AddingDocument
- `Model`: full record with all fields (member, is_new, active_section, editing_item, all draft_* fields, next_id)

**Functions (all pub) — copy from member_detail.gleam:**
- `blank_member_with_data() -> MemberWithData` (lines 133–152)
- `blank_allergy() -> Allergy` (lines 154–156)
- `blank_medication() -> Medication` (lines 158–166)
- `blank_immunization() -> Immunization` (lines 168–175)
- `blank_insurance() -> InsurancePolicy` (lines 177–185)
- `blank_provider() -> Provider` (lines 187–189)
- `blank_emergency_contact() -> EmergencyContact` (lines 191–193)
- `blank_document() -> Document` (lines 195–197)
- `model_from_member_with_data(mwd: MemberWithData, is_new: Bool) -> Model` (lines 199–220)

---

## Step 2 — Create `ui/src/pages/member_detail/views.gleam`

**Purpose:** Generic, reusable UI helpers. No knowledge of any specific Msg type.

**Imports:**
```
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
```

**Functions (all pub, all generic over type variable `msg`):**

- `labeled_input(label: String, input_type: String, value: String, on_input: fn(String) -> msg) -> Element(msg)`
  - Source: lines 1080–1100

- `save_cancel_buttons(save_msg: msg, cancel_msg: msg) -> Element(msg)`
  - Same layout as lines 1102–1123, but takes `cancel_msg` as a parameter instead of hardcoding `CancelEdit`

- `item_row_buttons(edit_msg: msg, delete_msg: msg) -> Element(msg)`
  - Source: lines 1125–1142

- `section_card(children: List(Element(msg))) -> Element(msg)`
  - Source: lines 1069–1078

**Gleam note:** Lowercase `msg` in a function signature is automatically a type variable — no special syntax needed.

---

## Step 3 — Create `ui/src/pages/member_detail/core_info.gleam`

**Imports:**
```
import data/mock_members.{MemberWithData, Member}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import pages/member_detail/types.{type Model, Model}
import pages/member_detail/views
```

**`Msg` type (pub):**
```
UpdateFirstName(String) | UpdateLastName(String) | UpdateEmail(String) |
UpdateDob(String) | UpdateRole(mock_members.Role) | ToggleManaged | SaveCoreInfo
```

**`update(model: types.Model, msg: Msg) -> types.Model` (pub)**
- Pure function, no Effect, no tuple. Delegates directly.
- Source logic: lines 236–262 of member_detail.gleam (all cases except SetSection, NavigateTo, CancelEdit)

**`view(model: types.Model) -> Element(Msg)` (pub)**
- Renders the personal info card. Source: lines 938–1023.
- Uses `views.labeled_input(...)` for text/email/date inputs.
- Role select and managed checkbox rendered inline.
- Save button emits `SaveCoreInfo`.

---

## Step 4 — Create `ui/src/pages/member_detail/allergies.gleam`

**Imports:**
```
import data/mock_members.{type Allergy, Allergy, MemberWithData}
import gleam/list
import gleam/option.{Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import pages/member_detail/types.{type Model, AddingAllergy, EditingAllergy, Model}
import pages/member_detail/views
```

**`Msg` type (pub):**
```
StartAdd | StartEdit(Int) | Delete(Int) | Save | CancelEdit |
UpdateName(String) | UpdateSeverity(String) | UpdateNotes(String)
```

**`update(model: types.Model, msg: Msg) -> types.Model` (pub)**
- CRUD on `model.member.allergies` / `model.draft_allergy`
- Source: lines 271–342

**`view(model: types.Model) -> Element(Msg)` (pub)**
- Uses `views.section_card`, `views.item_row_buttons`, `views.labeled_input`, `views.save_cancel_buttons(Save, CancelEdit)`
- Source: lines 1146–1216

---

## Step 5 — Create `ui/src/pages/member_detail/medications.gleam`

**Imports:**
```
import data/mock_members.{type Medication, Medication, MemberWithData}
import gleam/list
import gleam/option.{Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import pages/member_detail/types.{type Model, AddingMedication, EditingMedication, Model}
import pages/member_detail/views
```

**`Msg` type (pub):**
```
StartAdd | StartEdit(Int) | Delete(Int) | Save | CancelEdit |
UpdateName(String) | UpdateDosage(String) | UpdateFrequency(String) | UpdateProvider(String)
```

**`update(model: types.Model, msg: Msg) -> types.Model` (pub)**
- CRUD on `model.member.medications` / `model.draft_medication`
- Source: lines 344–437

**`view(model: types.Model) -> Element(Msg)` (pub)**
- Source: lines 1220–1304

---

## Step 6 — Create `ui/src/pages/member_detail/immunizations.gleam`

**Imports:**
```
import data/mock_members.{type Immunization, Immunization, MemberWithData}
import gleam/list
import gleam/option.{Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import pages/member_detail/types.{type Model, AddingImmunization, EditingImmunization, Model}
import pages/member_detail/views
```

**`Msg` type (pub):**
```
StartAdd | StartEdit(Int) | Delete(Int) | Save | CancelEdit |
UpdateVaccineName(String) | UpdateDateAdministered(String) | UpdateAdministeredBy(String)
```

**`update(model: types.Model, msg: Msg) -> types.Model` (pub)**
- CRUD on `model.member.immunizations` / `model.draft_immunization`
- Source: lines 439–533

**`view(model: types.Model) -> Element(Msg)` (pub)**
- Source: lines 1308–1386

---

## Step 7 — Create `ui/src/pages/member_detail/insurance.gleam`

**Imports:**
```
import data/mock_members.{type InsurancePolicy, InsurancePolicy, MemberWithData}
import gleam/list
import gleam/option.{Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import pages/member_detail/types.{type Model, AddingInsurance, EditingInsurance, Model}
import pages/member_detail/views
```

**`Msg` type (pub):**
```
StartAdd | StartEdit(Int) | Delete(Int) | Save | CancelEdit |
UpdateProviderName(String) | UpdatePolicyNumber(String) | UpdateGroupNumber(String) | UpdatePlanType(String)
```

**`update(model: types.Model, msg: Msg) -> types.Model` (pub)**
- CRUD on `model.member.insurance_policies` / `model.draft_insurance`
- Source: lines 535–639

**`view(model: types.Model) -> Element(Msg)` (pub)**
- Source: lines 1390–1473

---

## Step 8 — Create `ui/src/pages/member_detail/providers.gleam`

**Imports:**
```
import data/mock_members.{type Provider, Provider, MemberWithData}
import gleam/list
import gleam/option.{Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import pages/member_detail/types.{type Model, AddingProvider, EditingProvider, Model}
import pages/member_detail/views
```

**`Msg` type (pub):**
```
StartAdd | StartEdit(Int) | Delete(Int) | Save | CancelEdit |
UpdateName(String) | UpdateSpecialty(String) | UpdatePhone(String) | UpdateAddress(String)
```

**`update(model: types.Model, msg: Msg) -> types.Model` (pub)**
- CRUD on `model.member.providers` / `model.draft_provider`
- Source: lines 641–723

**`view(model: types.Model) -> Element(Msg)` (pub)**
- Source: lines 1477–1553

---

## Step 9 — Create `ui/src/pages/member_detail/emergency_contacts.gleam`

**Imports:**
```
import data/mock_members.{type EmergencyContact, EmergencyContact, MemberWithData}
import gleam/list
import gleam/option.{Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import pages/member_detail/types.{type Model, AddingEmergencyContact, EditingEmergencyContact, Model}
import pages/member_detail/views
```

**`Msg` type (pub):**
```
StartAdd | StartEdit(Int) | Delete(Int) | Save | CancelEdit |
UpdateName(String) | UpdateRelationship(String) | UpdatePhone(String)
```

**`update(model: types.Model, msg: Msg) -> types.Model` (pub)**
- CRUD on `model.member.emergency_contacts` / `model.draft_emergency_contact`
- Source: lines 725–823

**`view(model: types.Model) -> Element(Msg)` (pub)**
- Source: lines 1557–1635

---

## Step 10 — Create `ui/src/pages/member_detail/documents.gleam`

**Imports:**
```
import data/mock_members.{type Document, Document, MemberWithData}
import gleam/list
import gleam/option.{Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import pages/member_detail/types.{type Model, AddingDocument, EditingDocument, Model}
import pages/member_detail/views
```

**`Msg` type (pub):**
```
StartAdd | StartEdit(Int) | Delete(Int) | Save | CancelEdit |
UpdateName(String) | UpdateDocumentType(String) | UpdateNotes(String)
```

**`update(model: types.Model, msg: Msg) -> types.Model` (pub)**
- CRUD on `model.member.documents` / `model.draft_document`
- Source: lines 825–900

**`view(model: types.Model) -> Element(Msg)` (pub)**
- Source: lines 1639–1709

---

## Step 11 — Rewrite `ui/src/pages/member_detail.gleam` as thin orchestrator

**Imports:**
```
import components/navbar
import data/mock_members
import gleam/option.{type Option, Some}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import modem
import pages/member_detail/allergies
import pages/member_detail/core_info
import pages/member_detail/documents
import pages/member_detail/emergency_contacts
import pages/member_detail/immunizations
import pages/member_detail/insurance
import pages/member_detail/medications
import pages/member_detail/providers
import pages/member_detail/types
```

**Type alias (pub):**
```
pub type Model = types.Model
```

**Root `Msg` type (pub):**
```
pub type Msg {
  CoreInfoMsg(core_info.Msg)
  AllergyMsg(allergies.Msg)
  MedicationMsg(medications.Msg)
  ImmunizationMsg(immunizations.Msg)
  InsuranceMsg(insurance.Msg)
  ProviderMsg(providers.Msg)
  EmergencyContactMsg(emergency_contacts.Msg)
  DocumentMsg(documents.Msg)
  SetSection(types.Section)
  NavigateTo(String)
}
```

**`init(maybe_id: Option(Int)) -> #(types.Model, Effect(Msg))` (pub)**
- Uses `types.blank_member_with_data()` and `types.model_from_member_with_data()`
- Logic from lines 222–232

**`update(model: types.Model, msg: Msg) -> #(types.Model, Effect(Msg))` (pub)**
- Each arm delegates to sub-module and wraps in `#(updated_model, effect.none())`
- `CoreInfoMsg(sub_msg)` → `#(core_info.update(model, sub_msg), effect.none())`
- `AllergyMsg(sub_msg)` → `#(allergies.update(model, sub_msg), effect.none())`
- ... same pattern for all 8 sub-modules
- `SetSection(s)` → `#(types.Model(..model, active_section: s, editing_item: None), effect.none())`
- `NavigateTo(path)` → `#(model, modem.push(path, None, None))`

**`view(model: types.Model) -> Element(Msg)` (pub)**
- `html.div` root with navbar and main content
- `navbar.navbar(NavigateTo("/home"))`
- `page_header(model)` — private helper (lines 916–936), emits `NavigateTo` directly
- `element.map(core_info.view(model), CoreInfoMsg)`
- `section_tabs(model)` — private helper (lines 1025–1054), emits `SetSection` directly
- `section_content(model)` — private helper, matches on `model.active_section`:
  - `types.CoreInfo` → `element.text("")`
  - `types.Allergies` → `element.map(allergies.view(model), AllergyMsg)`
  - `types.Medications` → `element.map(medications.view(model), MedicationMsg)`
  - `types.Immunizations` → `element.map(immunizations.view(model), ImmunizationMsg)`
  - `types.Insurance` → `element.map(insurance.view(model), InsuranceMsg)`
  - `types.Providers` → `element.map(providers.view(model), ProviderMsg)`
  - `types.EmergencyContacts` → `element.map(emergency_contacts.view(model), EmergencyContactMsg)`
  - `types.Documents` → `element.map(documents.view(model), DocumentMsg)`

---

## Key Gleam notes for the Writer

1. **Generic functions:** Lowercase `msg` = type variable. No angle brackets. `fn foo(x: msg) -> Element(msg)` is correct.
2. **Type alias:** `pub type Model = types.Model` is valid Gleam.
3. **`element.map` shorthand:** `element.map(allergies.view(model), AllergyMsg)` works — `AllergyMsg` is `fn(allergies.Msg) -> Msg`.
4. **Import constructors explicitly:** `import pages/member_detail/types.{AddingAllergy, EditingAllergy, Model}` to use them unqualified.
5. **`pub fn` for all exported functions.** Private helpers stay `fn`.
6. **No circular imports:** types → mock_members only; views → lustre only; sections → types + views + mock_members + lustre; orchestrator → all sections.
7. **`save_cancel_buttons` change:** The new signature takes `cancel_msg` as a parameter. All call sites in section views must pass their own `CancelEdit` variant: `views.save_cancel_buttons(Save, CancelEdit)`.
