import data/mock_members.{Medication, MemberWithData}
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import pages/member_detail/types.{AddingMedication, EditingMedication, Model}
import pages/member_detail/views

pub type Msg {
  StartAdd
  StartEdit(Int)
  Delete(Int)
  Save
  CancelEdit
  UpdateName(String)
  UpdateDosage(String)
  UpdateFrequency(String)
  UpdateProvider(String)
}

pub fn update(model: types.Model, msg: Msg) -> types.Model {
  case msg {
    StartAdd ->
      Model(
        ..model,
        editing_item: Some(AddingMedication),
        draft_medication: types.blank_medication(),
      )
    StartEdit(id) -> {
      let found = list.find(model.member.medications, fn(m) { m.id == id })
      case found {
        Ok(m) ->
          Model(
            ..model,
            editing_item: Some(EditingMedication(id)),
            draft_medication: m,
          )
        Error(_) -> model
      }
    }
    Delete(id) -> {
      let new_list = list.filter(model.member.medications, fn(m) { m.id != id })
      let updated_mwd = MemberWithData(..model.member, medications: new_list)
      Model(..model, member: updated_mwd)
    }
    Save -> {
      case model.editing_item {
        Some(AddingMedication) -> {
          let new_item = Medication(..model.draft_medication, id: model.next_id)
          let new_list = list.append(model.member.medications, [new_item])
          let updated_mwd =
            MemberWithData(..model.member, medications: new_list)
          Model(
            ..model,
            member: updated_mwd,
            editing_item: None,
            next_id: model.next_id + 1,
          )
        }
        Some(EditingMedication(id)) -> {
          let new_list =
            list.map(model.member.medications, fn(m) {
              case m.id == id {
                True -> Medication(..model.draft_medication, id: id)
                False -> m
              }
            })
          let updated_mwd =
            MemberWithData(..model.member, medications: new_list)
          Model(..model, member: updated_mwd, editing_item: None)
        }
        _ -> model
      }
    }
    CancelEdit -> Model(..model, editing_item: None)
    UpdateName(v) ->
      Model(
        ..model,
        draft_medication: Medication(..model.draft_medication, name: v),
      )
    UpdateDosage(v) ->
      Model(
        ..model,
        draft_medication: Medication(..model.draft_medication, dosage: v),
      )
    UpdateFrequency(v) ->
      Model(
        ..model,
        draft_medication: Medication(..model.draft_medication, frequency: v),
      )
    UpdateProvider(v) ->
      Model(
        ..model,
        draft_medication: Medication(
          ..model.draft_medication,
          prescribing_provider: v,
        ),
      )
  }
}

pub fn view(model: types.Model) -> Element(Msg) {
  let is_adding = model.editing_item == Some(AddingMedication)
  let content = case model.member.medications {
    [] ->
      html.div([attribute.class("py-6 text-center")], [
        html.p([attribute.class("text-sm text-gray-400 italic mb-3")], [
          element.text("No medications recorded yet."),
        ]),
      ])
    _ ->
      html.div(
        [],
        list.map(model.member.medications, fn(m) {
          let is_editing = model.editing_item == Some(EditingMedication(m.id))
          case is_editing {
            True -> medication_form(model)
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
                      element.text(m.name),
                    ]),
                    html.p([attribute.class("text-sm text-gray-500")], [
                      element.text(m.dosage <> " — " <> m.frequency),
                    ]),
                    html.p([attribute.class("text-sm text-gray-500")], [
                      element.text("Provider: " <> m.prescribing_provider),
                    ]),
                  ]),
                  views.item_row_buttons(StartEdit(m.id), Delete(m.id)),
                ],
              )
          }
        }),
      )
  }
  let add_area = case is_adding {
    True -> medication_form(model)
    False ->
      html.button(
        [
          attribute.class(
            "mt-4 bg-teal-600 hover:bg-teal-700 text-white font-semibold py-2 px-4 rounded-lg transition-colors text-sm",
          ),
          event.on_click(StartAdd),
        ],
        [element.text("Add Medication")],
      )
  }
  views.section_card([
    html.h2([attribute.class("text-lg font-semibold text-gray-900 mb-4")], [
      element.text("Medications"),
    ]),
    content,
    add_area,
  ])
}

fn medication_form(model: types.Model) -> Element(Msg) {
  html.div([attribute.class("py-3 space-y-3")], [
    views.labeled_input("Name", "text", model.draft_medication.name, UpdateName),
    views.labeled_input(
      "Dosage",
      "text",
      model.draft_medication.dosage,
      UpdateDosage,
    ),
    views.labeled_input(
      "Frequency",
      "text",
      model.draft_medication.frequency,
      UpdateFrequency,
    ),
    views.labeled_input(
      "Prescribing Provider",
      "text",
      model.draft_medication.prescribing_provider,
      UpdateProvider,
    ),
    views.save_cancel_buttons(Save, CancelEdit),
  ])
}
