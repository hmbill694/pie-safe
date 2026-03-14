import components/navbar
import data/mock_members
import ffi/browser
import gleam/dynamic/decode
import gleam/int
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre_http
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

pub type Model =
  types.Model

pub type Msg {
  CoreInfoMsg(core_info.Msg)
  AllergyMsg(allergies.Msg)
  MedicationMsg(medications.Msg)
  ImmunizationMsg(immunizations.Msg)
  InsuranceMsg(insurance.Msg)
  ProviderMsg(providers.Msg)
  EmergencyContactMsg(emergency_contacts.Msg)
  DocumentMsg(documents.Msg)
  GotMember(Result(mock_members.MemberWithData, lustre_http.HttpError))
  NavigateTo(String)
  ToggleDropdown
  SignOut
}

pub fn init(maybe_id: Option(Int)) -> #(types.Model, Effect(Msg)) {
  case maybe_id {
    None -> {
      let model =
        types.model_from_member_with_data(
          types.blank_member_with_data(),
          True,
          types.Loaded,
        )
      #(model, effect.none())
    }
    Some(id) -> {
      let model =
        types.model_from_member_with_data(
          types.blank_member_with_data(),
          False,
          types.Loading,
        )
      #(model, fetch_member_effect(id))
    }
  }
}

pub fn update(model: types.Model, msg: Msg) -> #(types.Model, Effect(Msg)) {
  case msg {
    CoreInfoMsg(sub_msg) -> #(core_info.update(model, sub_msg), effect.none())
    AllergyMsg(sub_msg) -> #(allergies.update(model, sub_msg), effect.none())
    MedicationMsg(sub_msg) -> #(
      medications.update(model, sub_msg),
      effect.none(),
    )
    ImmunizationMsg(sub_msg) -> #(
      immunizations.update(model, sub_msg),
      effect.none(),
    )
    InsuranceMsg(sub_msg) -> #(insurance.update(model, sub_msg), effect.none())
    ProviderMsg(sub_msg) -> #(providers.update(model, sub_msg), effect.none())
    EmergencyContactMsg(sub_msg) -> #(
      emergency_contacts.update(model, sub_msg),
      effect.none(),
    )
    DocumentMsg(sub_msg) -> #(documents.update(model, sub_msg), effect.none())
    GotMember(Ok(mwd)) -> {
      let base = types.model_from_member_with_data(mwd, False, types.Loaded)
      #(
        types.Model(
          ..base,
          auth_email: model.auth_email,
          auth_role: model.auth_role,
          dropdown_open: model.dropdown_open,
        ),
        effect.none(),
      )
    }
    GotMember(Error(err)) -> {
      let message = case err {
        lustre_http.NetworkError -> "Network error — check your connection"
        lustre_http.NotFound -> "Member not found"
        lustre_http.Unauthorized -> "Unauthorized — please sign in again"
        lustre_http.InternalServerError(msg) -> "Server error: " <> msg
        lustre_http.OtherError(status, body) ->
          "HTTP " <> int.to_string(status) <> ": " <> body
        lustre_http.BadUrl(url) -> "Bad URL: " <> url
        lustre_http.JsonError(_) -> "Failed to parse server response"
      }
      #(
        types.Model(..model, load_state: types.LoadError(message)),
        effect.none(),
      )
    }
    NavigateTo(path) -> #(model, modem.push(path, None, None))
    ToggleDropdown -> #(
      types.Model(..model, dropdown_open: !model.dropdown_open),
      effect.none(),
    )
    SignOut -> #(model, modem.replace("/sign-in", None, None))
  }
}

pub fn view(model: types.Model) -> Element(Msg) {
  case model.load_state {
    types.Loading ->
      html.div(
        [
          attribute.class(
            "min-h-screen flex items-center justify-center bg-gray-50",
          ),
        ],
        [element.text("Loading...")],
      )
    types.LoadError(msg) ->
      html.div(
        [
          attribute.class(
            "min-h-screen flex items-center justify-center bg-gray-50",
          ),
        ],
        [
          html.div([attribute.class("text-center")], [
            html.p([attribute.class("text-red-600 font-medium mb-4")], [
              element.text("Error: " <> msg),
            ]),
            html.button(
              [
                attribute.class(
                  "text-teal-600 hover:text-teal-700 font-medium text-sm",
                ),
                event.on_click(NavigateTo("/home")),
              ],
              [element.text("← Back to Members")],
            ),
          ]),
        ],
      )
    types.Loaded -> loaded_view(model)
  }
}

fn loaded_view(model: types.Model) -> Element(Msg) {
  html.div([attribute.class("min-h-screen bg-gray-50")], [
    navbar.navbar(
      model.auth_email,
      model.auth_role,
      model.dropdown_open,
      ToggleDropdown,
      SignOut,
    ),
    html.main([attribute.class("max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8")], [
      page_header(model),
      element.map(core_info.view(model), CoreInfoMsg),
      html.div([attribute.class("space-y-6 mt-6")], [
        element.map(allergies.view(model), AllergyMsg),
        element.map(medications.view(model), MedicationMsg),
        element.map(immunizations.view(model), ImmunizationMsg),
        element.map(insurance.view(model), InsuranceMsg),
        element.map(providers.view(model), ProviderMsg),
        element.map(emergency_contacts.view(model), EmergencyContactMsg),
        element.map(documents.view(model), DocumentMsg),
      ]),
    ]),
  ])
}

fn page_header(model: types.Model) -> Element(Msg) {
  let title = case model.is_new {
    True -> "Add Member"
    False ->
      model.member.member.first_name <> " " <> model.member.member.last_name
  }
  html.div([attribute.class("flex items-center gap-4 mb-6")], [
    html.button(
      [
        attribute.class(
          "text-teal-600 hover:text-teal-700 font-medium text-sm flex items-center gap-1",
        ),
        event.on_click(NavigateTo("/home")),
      ],
      [element.text("← Back to Members")],
    ),
    html.h1([attribute.class("text-2xl font-bold text-gray-900")], [
      element.text(title),
    ]),
  ])
}

// ── JSON decoders ──

fn allergy_decoder() -> decode.Decoder(mock_members.Allergy) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("allergen", decode.string)
  use severity <- decode.field("severity", decode.string)
  use notes <- decode.field("notes", decode.string)
  decode.success(mock_members.Allergy(id:, name:, severity:, notes:))
}

fn medication_decoder() -> decode.Decoder(mock_members.Medication) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  use dosage <- decode.field("dosage", decode.string)
  use frequency <- decode.field("frequency", decode.string)
  use prescribing_provider <- decode.field(
    "prescribing_provider",
    decode.string,
  )
  decode.success(mock_members.Medication(
    id:,
    name:,
    dosage:,
    frequency:,
    prescribing_provider:,
  ))
}

fn immunization_decoder() -> decode.Decoder(mock_members.Immunization) {
  use id <- decode.field("id", decode.int)
  use vaccine_name <- decode.field("vaccine_name", decode.string)
  use date_administered <- decode.field("administered_at", decode.string)
  use administered_by <- decode.field("administered_by", decode.string)
  decode.success(mock_members.Immunization(
    id:,
    vaccine_name:,
    date_administered:,
    administered_by:,
  ))
}

fn insurance_decoder() -> decode.Decoder(mock_members.InsurancePolicy) {
  use id <- decode.field("id", decode.int)
  use provider_name <- decode.field("provider_name", decode.string)
  use policy_number <- decode.field("policy_number", decode.string)
  use group_number <- decode.field("group_number", decode.string)
  use plan_type <- decode.field("plan_type", decode.string)
  decode.success(mock_members.InsurancePolicy(
    id:,
    provider_name:,
    policy_number:,
    group_number:,
    plan_type:,
  ))
}

fn provider_decoder() -> decode.Decoder(mock_members.Provider) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  use specialty <- decode.field("specialty", decode.string)
  use phone <- decode.field("phone", decode.string)
  use address <- decode.field("address", decode.string)
  decode.success(mock_members.Provider(id:, name:, specialty:, phone:, address:))
}

fn emergency_contact_decoder() -> decode.Decoder(mock_members.EmergencyContact) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  use relationship <- decode.field("relationship", decode.string)
  use phone <- decode.field("phone", decode.string)
  decode.success(mock_members.EmergencyContact(
    id:,
    name:,
    relationship:,
    phone:,
  ))
}

fn document_decoder() -> decode.Decoder(mock_members.Document) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  use document_type <- decode.field("document_type", decode.string)
  use notes <- decode.field("notes", decode.string)
  decode.success(mock_members.Document(id:, name:, document_type:, notes:))
}

fn member_with_data_decoder() -> decode.Decoder(mock_members.MemberWithData) {
  use member <- decode.field("member", mock_members.member_decoder())
  use allergies <- decode.field("allergies", decode.list(allergy_decoder()))
  use medications <- decode.field(
    "medications",
    decode.list(medication_decoder()),
  )
  use immunizations <- decode.field(
    "immunizations",
    decode.list(immunization_decoder()),
  )
  use insurance_policies <- decode.field(
    "insurance",
    decode.list(insurance_decoder()),
  )
  use providers <- decode.field("providers", decode.list(provider_decoder()))
  use emergency_contacts <- decode.field(
    "emergency_contacts",
    decode.list(emergency_contact_decoder()),
  )
  use documents <- decode.field("documents", decode.list(document_decoder()))
  decode.success(mock_members.MemberWithData(
    member:,
    allergies:,
    medications:,
    immunizations:,
    insurance_policies:,
    providers:,
    emergency_contacts:,
    documents:,
  ))
}

fn fetch_member_effect(id: Int) -> Effect(Msg) {
  let url = browser.origin() <> "/api/members/" <> int.to_string(id)
  lustre_http.get(
    url,
    lustre_http.expect_json(member_with_data_decoder(), GotMember),
  )
}
