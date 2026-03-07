import data/mock_members.{Document, MemberWithData}
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import pages/member_detail/types.{AddingDocument, EditingDocument, Model}
import pages/member_detail/views

pub type Msg {
  StartAdd
  StartEdit(Int)
  Delete(Int)
  Save
  CancelEdit
  UpdateName(String)
  UpdateDocumentType(String)
  UpdateNotes(String)
}

pub fn update(model: types.Model, msg: Msg) -> types.Model {
  case msg {
    StartAdd ->
      Model(
        ..model,
        editing_item: Some(AddingDocument),
        draft_document: types.blank_document(),
      )
    StartEdit(id) -> {
      let found = list.find(model.member.documents, fn(d) { d.id == id })
      case found {
        Ok(d) ->
          Model(
            ..model,
            editing_item: Some(EditingDocument(id)),
            draft_document: d,
          )
        Error(_) -> model
      }
    }
    Delete(id) -> {
      let new_list = list.filter(model.member.documents, fn(d) { d.id != id })
      let updated_mwd = MemberWithData(..model.member, documents: new_list)
      Model(..model, member: updated_mwd)
    }
    Save -> {
      case model.editing_item {
        Some(AddingDocument) -> {
          let new_item = Document(..model.draft_document, id: model.next_id)
          let new_list = list.append(model.member.documents, [new_item])
          let updated_mwd = MemberWithData(..model.member, documents: new_list)
          Model(
            ..model,
            member: updated_mwd,
            editing_item: None,
            next_id: model.next_id + 1,
          )
        }
        Some(EditingDocument(id)) -> {
          let new_list =
            list.map(model.member.documents, fn(d) {
              case d.id == id {
                True -> Document(..model.draft_document, id: id)
                False -> d
              }
            })
          let updated_mwd = MemberWithData(..model.member, documents: new_list)
          Model(..model, member: updated_mwd, editing_item: None)
        }
        _ -> model
      }
    }
    CancelEdit -> Model(..model, editing_item: None)
    UpdateName(v) ->
      Model(..model, draft_document: Document(..model.draft_document, name: v))
    UpdateDocumentType(v) ->
      Model(
        ..model,
        draft_document: Document(..model.draft_document, document_type: v),
      )
    UpdateNotes(v) ->
      Model(..model, draft_document: Document(..model.draft_document, notes: v))
  }
}

pub fn view(model: types.Model) -> Element(Msg) {
  let is_adding = model.editing_item == Some(AddingDocument)
  let content = case model.member.documents {
    [] ->
      html.div([attribute.class("py-6 text-center")], [
        html.p([attribute.class("text-sm text-gray-400 italic mb-3")], [
          element.text("No documents recorded yet."),
        ]),
      ])
    _ ->
      html.div(
        [],
        list.map(model.member.documents, fn(d) {
          let is_editing = model.editing_item == Some(EditingDocument(d.id))
          case is_editing {
            True -> document_form(model)
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
                      element.text(d.name),
                    ]),
                    html.p([attribute.class("text-sm text-gray-500")], [
                      element.text(d.document_type),
                    ]),
                    html.p([attribute.class("text-sm text-gray-500")], [
                      element.text(d.notes),
                    ]),
                  ]),
                  views.item_row_buttons(StartEdit(d.id), Delete(d.id)),
                ],
              )
          }
        }),
      )
  }
  let add_area = case is_adding {
    True -> document_form(model)
    False ->
      html.button(
        [
          attribute.class(
            "mt-4 bg-teal-600 hover:bg-teal-700 text-white font-semibold py-2 px-4 rounded-lg transition-colors text-sm",
          ),
          event.on_click(StartAdd),
        ],
        [element.text("Add Document")],
      )
  }
  views.section_card([
    html.h2([attribute.class("text-lg font-semibold text-gray-900 mb-4")], [
      element.text("Documents"),
    ]),
    content,
    add_area,
  ])
}

fn document_form(model: types.Model) -> Element(Msg) {
  html.div([attribute.class("py-3 space-y-3")], [
    views.labeled_input("Name", "text", model.draft_document.name, UpdateName),
    views.labeled_input(
      "Document Type",
      "text",
      model.draft_document.document_type,
      UpdateDocumentType,
    ),
    views.labeled_input(
      "Notes",
      "text",
      model.draft_document.notes,
      UpdateNotes,
    ),
    views.save_cancel_buttons(Save, CancelEdit),
  ])
}
