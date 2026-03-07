# Requirements: Refactor member_detail.gleam into sub-modules

## Goal
Break the monolithic `ui/src/pages/member_detail.gleam` (1709 lines) into a modular structure where each health data section is its own self-contained Gleam module. `member_detail.gleam` remains the single public API surface that `ui.gleam` interacts with.

## Motivation
- The file is too large to work on meaningfully
- Each health section (allergies, medications, etc.) is logically independent
- Aligns with the Lustre composable architecture pattern (same pattern as ui.gleam → home.gleam)

## Target file structure

```
ui/src/pages/
  member_detail.gleam                  ← thin orchestrator (public API, unchanged interface for ui.gleam)
  member_detail/
    types.gleam                        ← shared types: Model, Section, EditTarget, blank helpers
    views.gleam                        ← shared view helpers: labeled_input, save_cancel_buttons, item_row_buttons, section_card
    core_info.gleam                    ← core member fields section
    allergies.gleam                    ← allergies section
    medications.gleam                  ← medications section
    immunizations.gleam                ← immunizations section
    insurance.gleam                    ← insurance section
    providers.gleam                    ← providers section
    emergency_contacts.gleam           ← emergency contacts section
    documents.gleam                    ← documents section
```

## Architecture: composable Lustre sub-modules

Each health section module (`allergies.gleam`, `medications.gleam`, etc.) follows the same pattern:

```gleam
// Each section module owns:
pub type Msg { ... }            // field update + CRUD messages for this section only
pub fn update(model: types.Model, msg: Msg) -> types.Model   // returns updated model (no effects needed)
pub fn view(model: types.Model) -> Element(Msg)              // renders this section's UI
```

`core_info.gleam` follows the same pattern for the personal information form.

`member_detail.gleam` owns the root `Msg` union that wraps each sub-module:

```gleam
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

## Module responsibilities

### `member_detail/types.gleam`
- `Section` type
- `EditTarget` type  
- `Model` type
- All blank helper functions: `blank_allergy()`, `blank_medication()`, etc.
- `blank_member_with_data()`
- `model_from_member_with_data(mwd, is_new)`
- All of these should be `pub` (needed by other sub-modules)

### `member_detail/views.gleam`
- `labeled_input(label, input_type, value, on_input) -> Element(msg)` — generic over msg type
- `save_cancel_buttons(save_msg, cancel_msg) -> Element(msg)` — generic over msg type (cancel_msg passed in rather than hardcoded to CancelEdit, since each sub-module has its own CancelEdit variant)
- `item_row_buttons(edit_msg, delete_msg) -> Element(msg)` — generic over msg type
- `section_card(children) -> Element(msg)` — generic over msg type
- All should be `pub` and generic over `msg` (using Gleam's type parameters)

### `member_detail/core_info.gleam`
- `Msg` type: `UpdateFirstName(String)`, `UpdateLastName(String)`, `UpdateEmail(String)`, `UpdateDob(String)`, `UpdateRole(Role)`, `ToggleManaged`, `SaveCoreInfo`
- `update(model: types.Model, msg: Msg) -> types.Model`
- `view(model: types.Model) -> Element(Msg)`
- No CancelEdit needed (core info is always visible, no inline editing state)

### Each health section module (`allergies.gleam`, etc.)
- `Msg` type: field updates + `StartAdd`, `StartEdit(Int)`, `Delete(Int)`, `Save`, `CancelEdit`
- `update(model: types.Model, msg: Msg) -> types.Model` — returns the full updated model
- `view(model: types.Model) -> Element(Msg)`

### `member_detail.gleam` (thin orchestrator)
- `pub type Msg { ... }` — wraps all sub-module Msg types + SetSection + NavigateTo
- `pub type Model = types.Model` — re-exports via type alias (or just re-exports from types)
- `pub fn init(maybe_id: Option(Int)) -> #(types.Model, Effect(Msg))`
- `pub fn update(model: types.Model, msg: Msg) -> #(types.Model, Effect(Msg))`
  - Delegates to sub-module update functions, wraps effects with `effect.none()` (sub-modules have no effects)
  - Handles `SetSection` and `NavigateTo` directly
- `pub fn view(model: types.Model) -> Element(Msg)`
  - Uses `element.map(sub_view, SubMsg)` to lift sub-module views into the root Msg type
  - Renders navbar, page header, core info, section tabs, section content area

## Constraints
- `ui.gleam` must not need to change — the public interface of `member_detail.gleam` stays the same: `init`, `update`, `view`, and `Model`/`Msg` types
- No new dependencies
- All sub-module view functions must be lifted with `element.map` so the DOM events propagate correctly up to the root Msg type
- Gleam does not allow circular imports — `types.gleam` and `views.gleam` must not import any sibling modules
