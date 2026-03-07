import data/mock_members.{InsurancePolicy, MemberWithData}
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import pages/member_detail/types.{AddingInsurance, EditingInsurance, Model}
import pages/member_detail/views

pub type Msg {
  StartAdd
  StartEdit(Int)
  Delete(Int)
  Save
  CancelEdit
  UpdateProviderName(String)
  UpdatePolicyNumber(String)
  UpdateGroupNumber(String)
  UpdatePlanType(String)
}

pub fn update(model: types.Model, msg: Msg) -> types.Model {
  case msg {
    StartAdd ->
      Model(
        ..model,
        editing_item: Some(AddingInsurance),
        draft_insurance: types.blank_insurance(),
      )
    StartEdit(id) -> {
      let found =
        list.find(model.member.insurance_policies, fn(p) { p.id == id })
      case found {
        Ok(p) ->
          Model(
            ..model,
            editing_item: Some(EditingInsurance(id)),
            draft_insurance: p,
          )
        Error(_) -> model
      }
    }
    Delete(id) -> {
      let new_list =
        list.filter(model.member.insurance_policies, fn(p) { p.id != id })
      let updated_mwd =
        MemberWithData(..model.member, insurance_policies: new_list)
      Model(..model, member: updated_mwd)
    }
    Save -> {
      case model.editing_item {
        Some(AddingInsurance) -> {
          let new_item =
            InsurancePolicy(..model.draft_insurance, id: model.next_id)
          let new_list =
            list.append(model.member.insurance_policies, [new_item])
          let updated_mwd =
            MemberWithData(..model.member, insurance_policies: new_list)
          Model(
            ..model,
            member: updated_mwd,
            editing_item: None,
            next_id: model.next_id + 1,
          )
        }
        Some(EditingInsurance(id)) -> {
          let new_list =
            list.map(model.member.insurance_policies, fn(p) {
              case p.id == id {
                True -> InsurancePolicy(..model.draft_insurance, id: id)
                False -> p
              }
            })
          let updated_mwd =
            MemberWithData(..model.member, insurance_policies: new_list)
          Model(..model, member: updated_mwd, editing_item: None)
        }
        _ -> model
      }
    }
    CancelEdit -> Model(..model, editing_item: None)
    UpdateProviderName(v) ->
      Model(
        ..model,
        draft_insurance: InsurancePolicy(
          ..model.draft_insurance,
          provider_name: v,
        ),
      )
    UpdatePolicyNumber(v) ->
      Model(
        ..model,
        draft_insurance: InsurancePolicy(
          ..model.draft_insurance,
          policy_number: v,
        ),
      )
    UpdateGroupNumber(v) ->
      Model(
        ..model,
        draft_insurance: InsurancePolicy(
          ..model.draft_insurance,
          group_number: v,
        ),
      )
    UpdatePlanType(v) ->
      Model(
        ..model,
        draft_insurance: InsurancePolicy(..model.draft_insurance, plan_type: v),
      )
  }
}

pub fn view(model: types.Model) -> Element(Msg) {
  let is_adding = model.editing_item == Some(AddingInsurance)
  let content = case model.member.insurance_policies {
    [] ->
      html.div([attribute.class("py-6 text-center")], [
        html.p([attribute.class("text-sm text-gray-400 italic mb-3")], [
          element.text("No insurance policies recorded yet."),
        ]),
      ])
    _ ->
      html.div(
        [],
        list.map(model.member.insurance_policies, fn(p) {
          let is_editing = model.editing_item == Some(EditingInsurance(p.id))
          case is_editing {
            True -> insurance_form(model)
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
                      element.text(p.provider_name),
                    ]),
                    html.p([attribute.class("text-sm text-gray-500")], [
                      element.text("Policy: " <> p.policy_number),
                    ]),
                    html.p([attribute.class("text-sm text-gray-500")], [
                      element.text(
                        "Group: " <> p.group_number <> " — " <> p.plan_type,
                      ),
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
    True -> insurance_form(model)
    False ->
      html.button(
        [
          attribute.class(
            "mt-4 bg-teal-600 hover:bg-teal-700 text-white font-semibold py-2 px-4 rounded-lg transition-colors text-sm",
          ),
          event.on_click(StartAdd),
        ],
        [element.text("Add Insurance Policy")],
      )
  }
  views.section_card([
    html.h2([attribute.class("text-lg font-semibold text-gray-900 mb-4")], [
      element.text("Insurance Policies"),
    ]),
    content,
    add_area,
  ])
}

fn insurance_form(model: types.Model) -> Element(Msg) {
  html.div([attribute.class("py-3 space-y-3")], [
    views.labeled_input(
      "Provider Name",
      "text",
      model.draft_insurance.provider_name,
      UpdateProviderName,
    ),
    views.labeled_input(
      "Policy Number",
      "text",
      model.draft_insurance.policy_number,
      UpdatePolicyNumber,
    ),
    views.labeled_input(
      "Group Number",
      "text",
      model.draft_insurance.group_number,
      UpdateGroupNumber,
    ),
    views.labeled_input(
      "Plan Type",
      "text",
      model.draft_insurance.plan_type,
      UpdatePlanType,
    ),
    views.save_cancel_buttons(Save, CancelEdit),
  ])
}
