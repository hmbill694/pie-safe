import data/mock_members.{Immunization, MemberWithData}
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import pages/member_detail/types.{AddingImmunization, EditingImmunization, Model}
import pages/member_detail/views

pub type Msg {
  StartAdd
  StartEdit(Int)
  Delete(Int)
  Save
  CancelEdit
  UpdateVaccineName(String)
  UpdateDateAdministered(String)
  UpdateAdministeredBy(String)
}

pub fn update(model: types.Model, msg: Msg) -> types.Model {
  case msg {
    StartAdd ->
      Model(
        ..model,
        editing_item: Some(AddingImmunization),
        draft_immunization: types.blank_immunization(),
      )
    StartEdit(id) -> {
      let found = list.find(model.member.immunizations, fn(i) { i.id == id })
      case found {
        Ok(i) ->
          Model(
            ..model,
            editing_item: Some(EditingImmunization(id)),
            draft_immunization: i,
          )
        Error(_) -> model
      }
    }
    Delete(id) -> {
      let new_list =
        list.filter(model.member.immunizations, fn(i) { i.id != id })
      let updated_mwd = MemberWithData(..model.member, immunizations: new_list)
      Model(..model, member: updated_mwd)
    }
    Save -> {
      case model.editing_item {
        Some(AddingImmunization) -> {
          let new_item =
            Immunization(..model.draft_immunization, id: model.next_id)
          let new_list = list.append(model.member.immunizations, [new_item])
          let updated_mwd =
            MemberWithData(..model.member, immunizations: new_list)
          Model(
            ..model,
            member: updated_mwd,
            editing_item: None,
            next_id: model.next_id + 1,
          )
        }
        Some(EditingImmunization(id)) -> {
          let new_list =
            list.map(model.member.immunizations, fn(i) {
              case i.id == id {
                True -> Immunization(..model.draft_immunization, id: id)
                False -> i
              }
            })
          let updated_mwd =
            MemberWithData(..model.member, immunizations: new_list)
          Model(..model, member: updated_mwd, editing_item: None)
        }
        _ -> model
      }
    }
    CancelEdit -> Model(..model, editing_item: None)
    UpdateVaccineName(v) ->
      Model(
        ..model,
        draft_immunization: Immunization(
          ..model.draft_immunization,
          vaccine_name: v,
        ),
      )
    UpdateDateAdministered(v) ->
      Model(
        ..model,
        draft_immunization: Immunization(
          ..model.draft_immunization,
          date_administered: v,
        ),
      )
    UpdateAdministeredBy(v) ->
      Model(
        ..model,
        draft_immunization: Immunization(
          ..model.draft_immunization,
          administered_by: v,
        ),
      )
  }
}

pub fn view(model: types.Model) -> Element(Msg) {
  let is_adding = model.editing_item == Some(AddingImmunization)
  let content = case model.member.immunizations {
    [] ->
      html.div([attribute.class("py-6 text-center")], [
        html.p([attribute.class("text-sm text-gray-400 italic mb-3")], [
          element.text("No immunizations recorded yet."),
        ]),
      ])
    _ ->
      html.div(
        [],
        list.map(model.member.immunizations, fn(i) {
          let is_editing = model.editing_item == Some(EditingImmunization(i.id))
          case is_editing {
            True -> immunization_form(model)
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
                      element.text(i.vaccine_name),
                    ]),
                    html.p([attribute.class("text-sm text-gray-500")], [
                      element.text("Administered: " <> i.date_administered),
                    ]),
                    html.p([attribute.class("text-sm text-gray-500")], [
                      element.text("By: " <> i.administered_by),
                    ]),
                  ]),
                  views.item_row_buttons(StartEdit(i.id), Delete(i.id)),
                ],
              )
          }
        }),
      )
  }
  let add_area = case is_adding {
    True -> immunization_form(model)
    False ->
      html.button(
        [
          attribute.class(
            "mt-4 bg-teal-600 hover:bg-teal-700 text-white font-semibold py-2 px-4 rounded-lg transition-colors text-sm",
          ),
          event.on_click(StartAdd),
        ],
        [element.text("Add Immunization")],
      )
  }
  views.section_card([
    html.h2([attribute.class("text-lg font-semibold text-gray-900 mb-4")], [
      element.text("Immunizations"),
    ]),
    content,
    add_area,
  ])
}

fn immunization_form(model: types.Model) -> Element(Msg) {
  html.div([attribute.class("py-3 space-y-3")], [
    views.labeled_input(
      "Vaccine Name",
      "text",
      model.draft_immunization.vaccine_name,
      UpdateVaccineName,
    ),
    views.labeled_input(
      "Date Administered",
      "date",
      model.draft_immunization.date_administered,
      UpdateDateAdministered,
    ),
    views.labeled_input(
      "Administered By",
      "text",
      model.draft_immunization.administered_by,
      UpdateAdministeredBy,
    ),
    views.save_cancel_buttons(Save, CancelEdit),
  ])
}
