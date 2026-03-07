import data/mock_members.{Allergy, MemberWithData}
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import pages/member_detail/types.{AddingAllergy, EditingAllergy, Model}
import pages/member_detail/views

pub type Msg {
  StartAdd
  StartEdit(Int)
  Delete(Int)
  Save
  CancelEdit
  UpdateName(String)
  UpdateSeverity(String)
  UpdateNotes(String)
}

pub fn update(model: types.Model, msg: Msg) -> types.Model {
  case msg {
    StartAdd ->
      Model(
        ..model,
        editing_item: Some(AddingAllergy),
        draft_allergy: types.blank_allergy(),
      )
    StartEdit(id) -> {
      let found = list.find(model.member.allergies, fn(a) { a.id == id })
      case found {
        Ok(a) ->
          Model(
            ..model,
            editing_item: Some(EditingAllergy(id)),
            draft_allergy: a,
          )
        Error(_) -> model
      }
    }
    Delete(id) -> {
      let new_list = list.filter(model.member.allergies, fn(a) { a.id != id })
      let updated_mwd = MemberWithData(..model.member, allergies: new_list)
      Model(..model, member: updated_mwd)
    }
    Save -> {
      case model.editing_item {
        Some(AddingAllergy) -> {
          let new_item = Allergy(..model.draft_allergy, id: model.next_id)
          let new_list = list.append(model.member.allergies, [new_item])
          let updated_mwd = MemberWithData(..model.member, allergies: new_list)
          Model(
            ..model,
            member: updated_mwd,
            editing_item: None,
            next_id: model.next_id + 1,
          )
        }
        Some(EditingAllergy(id)) -> {
          let new_list =
            list.map(model.member.allergies, fn(a) {
              case a.id == id {
                True -> Allergy(..model.draft_allergy, id: id)
                False -> a
              }
            })
          let updated_mwd = MemberWithData(..model.member, allergies: new_list)
          Model(..model, member: updated_mwd, editing_item: None)
        }
        _ -> model
      }
    }
    CancelEdit -> Model(..model, editing_item: None)
    UpdateName(v) ->
      Model(..model, draft_allergy: Allergy(..model.draft_allergy, name: v))
    UpdateSeverity(v) ->
      Model(..model, draft_allergy: Allergy(..model.draft_allergy, severity: v))
    UpdateNotes(v) ->
      Model(..model, draft_allergy: Allergy(..model.draft_allergy, notes: v))
  }
}

pub fn view(model: types.Model) -> Element(Msg) {
  let is_adding = model.editing_item == Some(AddingAllergy)
  let content = case model.member.allergies {
    [] ->
      html.div([attribute.class("py-6 text-center")], [
        html.p([attribute.class("text-sm text-gray-400 italic mb-3")], [
          element.text("No allergies recorded yet."),
        ]),
      ])
    _ ->
      html.div(
        [],
        list.map(model.member.allergies, fn(a) {
          let is_editing = model.editing_item == Some(EditingAllergy(a.id))
          case is_editing {
            True -> allergy_form(model)
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
                      element.text(a.name),
                    ]),
                    html.p([attribute.class("text-sm text-gray-500")], [
                      element.text("Severity: " <> a.severity),
                    ]),
                    html.p([attribute.class("text-sm text-gray-500")], [
                      element.text(a.notes),
                    ]),
                  ]),
                  views.item_row_buttons(StartEdit(a.id), Delete(a.id)),
                ],
              )
          }
        }),
      )
  }
  let add_area = case is_adding {
    True -> allergy_form(model)
    False ->
      html.button(
        [
          attribute.class(
            "mt-4 bg-teal-600 hover:bg-teal-700 text-white font-semibold py-2 px-4 rounded-lg transition-colors text-sm",
          ),
          event.on_click(StartAdd),
        ],
        [element.text("Add Allergy")],
      )
  }
  views.section_card([
    html.h2([attribute.class("text-lg font-semibold text-gray-900 mb-4")], [
      element.text("Allergies"),
    ]),
    content,
    add_area,
  ])
}

fn allergy_form(model: types.Model) -> Element(Msg) {
  html.div([attribute.class("py-3 space-y-3")], [
    views.labeled_input("Name", "text", model.draft_allergy.name, UpdateName),
    views.labeled_input(
      "Severity",
      "text",
      model.draft_allergy.severity,
      UpdateSeverity,
    ),
    views.labeled_input("Notes", "text", model.draft_allergy.notes, UpdateNotes),
    views.save_cancel_buttons(Save, CancelEdit),
  ])
}
