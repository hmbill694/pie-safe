import data/mock_members.{MemberWithData, Provider}
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import pages/member_detail/types.{AddingProvider, EditingProvider, Model}
import pages/member_detail/views

pub type Msg {
  StartAdd
  StartEdit(Int)
  Delete(Int)
  Save
  CancelEdit
  UpdateName(String)
  UpdateSpecialty(String)
  UpdatePhone(String)
  UpdateAddress(String)
}

pub fn update(model: types.Model, msg: Msg) -> types.Model {
  case msg {
    StartAdd ->
      Model(
        ..model,
        editing_item: Some(AddingProvider),
        draft_provider: types.blank_provider(),
      )
    StartEdit(id) -> {
      let found = list.find(model.member.providers, fn(p) { p.id == id })
      case found {
        Ok(p) ->
          Model(
            ..model,
            editing_item: Some(EditingProvider(id)),
            draft_provider: p,
          )
        Error(_) -> model
      }
    }
    Delete(id) -> {
      let new_list = list.filter(model.member.providers, fn(p) { p.id != id })
      let updated_mwd = MemberWithData(..model.member, providers: new_list)
      Model(..model, member: updated_mwd)
    }
    Save -> {
      case model.editing_item {
        Some(AddingProvider) -> {
          let new_item = Provider(..model.draft_provider, id: model.next_id)
          let new_list = list.append(model.member.providers, [new_item])
          let updated_mwd = MemberWithData(..model.member, providers: new_list)
          Model(
            ..model,
            member: updated_mwd,
            editing_item: None,
            next_id: model.next_id + 1,
          )
        }
        Some(EditingProvider(id)) -> {
          let new_list =
            list.map(model.member.providers, fn(p) {
              case p.id == id {
                True -> Provider(..model.draft_provider, id: id)
                False -> p
              }
            })
          let updated_mwd = MemberWithData(..model.member, providers: new_list)
          Model(..model, member: updated_mwd, editing_item: None)
        }
        _ -> model
      }
    }
    CancelEdit -> Model(..model, editing_item: None)
    UpdateName(v) ->
      Model(..model, draft_provider: Provider(..model.draft_provider, name: v))
    UpdateSpecialty(v) ->
      Model(
        ..model,
        draft_provider: Provider(..model.draft_provider, specialty: v),
      )
    UpdatePhone(v) ->
      Model(..model, draft_provider: Provider(..model.draft_provider, phone: v))
    UpdateAddress(v) ->
      Model(
        ..model,
        draft_provider: Provider(..model.draft_provider, address: v),
      )
  }
}

pub fn view(model: types.Model) -> Element(Msg) {
  let is_adding = model.editing_item == Some(AddingProvider)
  let content = case model.member.providers {
    [] ->
      html.div([attribute.class("py-6 text-center")], [
        html.p([attribute.class("text-sm text-gray-400 italic mb-3")], [
          element.text("No providers recorded yet."),
        ]),
      ])
    _ ->
      html.div(
        [],
        list.map(model.member.providers, fn(p) {
          let is_editing = model.editing_item == Some(EditingProvider(p.id))
          case is_editing {
            True -> provider_form(model)
            False ->
              html.div(
                [
                  attribute.class(
                    "flex items-center justify-between py-3 border-b border-gray-100 last:border-0",
                  ),
                ],
                [
                  html.div([], [
                    html.p([attribute.class("font-medium text-gray-900")], [
                      element.text(p.name),
                    ]),
                    html.p([attribute.class("text-sm text-gray-500")], [
                      element.text(p.specialty),
                    ]),
                    html.p([attribute.class("text-sm text-gray-500")], [
                      element.text(p.phone <> " — " <> p.address),
                    ]),
                  ]),
                  views.item_row_buttons(StartEdit(p.id), Delete(p.id)),
                ],
              )
          }
        }),
      )
  }
  let add_area = case is_adding {
    True -> provider_form(model)
    False ->
      html.button(
        [
          attribute.class(
            "mt-4 bg-teal-600 hover:bg-teal-700 text-white font-semibold py-2 px-4 rounded-lg transition-colors text-sm",
          ),
          event.on_click(StartAdd),
        ],
        [element.text("Add Provider")],
      )
  }
  views.section_card([
    html.h2([attribute.class("text-lg font-semibold text-gray-900 mb-4")], [
      element.text("Healthcare Providers"),
    ]),
    content,
    add_area,
  ])
}

fn provider_form(model: types.Model) -> Element(Msg) {
  html.div([attribute.class("py-3 space-y-3")], [
    views.labeled_input("Name", "text", model.draft_provider.name, UpdateName),
    views.labeled_input(
      "Specialty",
      "text",
      model.draft_provider.specialty,
      UpdateSpecialty,
    ),
    views.labeled_input("Phone", "tel", model.draft_provider.phone, UpdatePhone),
    views.labeled_input(
      "Address",
      "text",
      model.draft_provider.address,
      UpdateAddress,
    ),
    views.save_cancel_buttons(Save, CancelEdit),
  ])
}
