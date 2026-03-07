import data/mock_members.{EmergencyContact, MemberWithData}
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import pages/member_detail/types.{
  AddingEmergencyContact, EditingEmergencyContact, Model,
}
import pages/member_detail/views

pub type Msg {
  StartAdd
  StartEdit(Int)
  Delete(Int)
  Save
  CancelEdit
  UpdateName(String)
  UpdateRelationship(String)
  UpdatePhone(String)
}

pub fn update(model: types.Model, msg: Msg) -> types.Model {
  case msg {
    StartAdd ->
      Model(
        ..model,
        editing_item: Some(AddingEmergencyContact),
        draft_emergency_contact: types.blank_emergency_contact(),
      )
    StartEdit(id) -> {
      let found =
        list.find(model.member.emergency_contacts, fn(c) { c.id == id })
      case found {
        Ok(c) ->
          Model(
            ..model,
            editing_item: Some(EditingEmergencyContact(id)),
            draft_emergency_contact: c,
          )
        Error(_) -> model
      }
    }
    Delete(id) -> {
      let new_list =
        list.filter(model.member.emergency_contacts, fn(c) { c.id != id })
      let updated_mwd =
        MemberWithData(..model.member, emergency_contacts: new_list)
      Model(..model, member: updated_mwd)
    }
    Save -> {
      case model.editing_item {
        Some(AddingEmergencyContact) -> {
          let new_item =
            EmergencyContact(..model.draft_emergency_contact, id: model.next_id)
          let new_list =
            list.append(model.member.emergency_contacts, [new_item])
          let updated_mwd =
            MemberWithData(..model.member, emergency_contacts: new_list)
          Model(
            ..model,
            member: updated_mwd,
            editing_item: None,
            next_id: model.next_id + 1,
          )
        }
        Some(EditingEmergencyContact(id)) -> {
          let new_list =
            list.map(model.member.emergency_contacts, fn(c) {
              case c.id == id {
                True ->
                  EmergencyContact(..model.draft_emergency_contact, id: id)
                False -> c
              }
            })
          let updated_mwd =
            MemberWithData(..model.member, emergency_contacts: new_list)
          Model(..model, member: updated_mwd, editing_item: None)
        }
        _ -> model
      }
    }
    CancelEdit -> Model(..model, editing_item: None)
    UpdateName(v) ->
      Model(
        ..model,
        draft_emergency_contact: EmergencyContact(
          ..model.draft_emergency_contact,
          name: v,
        ),
      )
    UpdateRelationship(v) ->
      Model(
        ..model,
        draft_emergency_contact: EmergencyContact(
          ..model.draft_emergency_contact,
          relationship: v,
        ),
      )
    UpdatePhone(v) ->
      Model(
        ..model,
        draft_emergency_contact: EmergencyContact(
          ..model.draft_emergency_contact,
          phone: v,
        ),
      )
  }
}

pub fn view(model: types.Model) -> Element(Msg) {
  let is_adding = model.editing_item == Some(AddingEmergencyContact)
  let content = case model.member.emergency_contacts {
    [] ->
      html.div([attribute.class("py-6 text-center")], [
        html.p([attribute.class("text-sm text-gray-400 italic mb-3")], [
          element.text("No emergency contacts recorded yet."),
        ]),
      ])
    _ ->
      html.div(
        [],
        list.map(model.member.emergency_contacts, fn(c) {
          let is_editing =
            model.editing_item == Some(EditingEmergencyContact(c.id))
          case is_editing {
            True -> emergency_contact_form(model)
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
                      element.text(c.name),
                    ]),
                    html.p([attribute.class("text-sm text-gray-500")], [
                      element.text(c.relationship),
                    ]),
                    html.p([attribute.class("text-sm text-gray-500")], [
                      element.text(c.phone),
                    ]),
                  ]),
                  views.item_row_buttons(StartEdit(c.id), Delete(c.id)),
                ],
              )
          }
        }),
      )
  }
  let add_area = case is_adding {
    True -> emergency_contact_form(model)
    False ->
      html.button(
        [
          attribute.class(
            "mt-4 bg-teal-600 hover:bg-teal-700 text-white font-semibold py-2 px-4 rounded-lg transition-colors text-sm",
          ),
          event.on_click(StartAdd),
        ],
        [element.text("Add Emergency Contact")],
      )
  }
  views.section_card([
    html.h2([attribute.class("text-lg font-semibold text-gray-900 mb-4")], [
      element.text("Emergency Contacts"),
    ]),
    content,
    add_area,
  ])
}

fn emergency_contact_form(model: types.Model) -> Element(Msg) {
  html.div([attribute.class("py-3 space-y-3")], [
    views.labeled_input(
      "Name",
      "text",
      model.draft_emergency_contact.name,
      UpdateName,
    ),
    views.labeled_input(
      "Relationship",
      "text",
      model.draft_emergency_contact.relationship,
      UpdateRelationship,
    ),
    views.labeled_input(
      "Phone",
      "tel",
      model.draft_emergency_contact.phone,
      UpdatePhone,
    ),
    views.save_cancel_buttons(Save, CancelEdit),
  ])
}
