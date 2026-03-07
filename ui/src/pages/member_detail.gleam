import components/navbar
import data/mock_members
import gleam/option.{type Option, None, Some}
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
  NavigateTo(String)
}

pub fn init(maybe_id: Option(Int)) -> #(types.Model, Effect(Msg)) {
  let model = case maybe_id {
    Some(id) ->
      case mock_members.get_member_by_id(id) {
        Some(mwd) -> types.model_from_member_with_data(mwd, False)
        None ->
          types.model_from_member_with_data(
            types.blank_member_with_data(),
            True,
          )
      }
    None ->
      types.model_from_member_with_data(types.blank_member_with_data(), True)
  }
  #(model, effect.none())
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
    NavigateTo(path) -> #(model, modem.push(path, None, None))
  }
}

pub fn view(model: types.Model) -> Element(Msg) {
  html.div([attribute.class("min-h-screen bg-gray-50")], [
    navbar.navbar(NavigateTo("/home")),
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
