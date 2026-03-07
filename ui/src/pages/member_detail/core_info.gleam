import data/mock_members.{MemberWithData}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import pages/member_detail/types.{Model}
import pages/member_detail/views

pub type Msg {
  UpdateFirstName(String)
  UpdateLastName(String)
  UpdateEmail(String)
  UpdateDob(String)
  UpdateRole(mock_members.Role)
  ToggleManaged
  SaveCoreInfo
}

pub fn update(model: types.Model, msg: Msg) -> types.Model {
  case msg {
    UpdateFirstName(v) -> Model(..model, draft_first_name: v)
    UpdateLastName(v) -> Model(..model, draft_last_name: v)
    UpdateEmail(v) -> Model(..model, draft_email: v)
    UpdateDob(v) -> Model(..model, draft_dob: v)
    UpdateRole(v) -> Model(..model, draft_role: v)
    ToggleManaged ->
      Model(..model, draft_is_managed: case model.draft_is_managed {
        True -> False
        False -> True
      })
    SaveCoreInfo -> {
      let old = model.member.member
      let updated_member =
        mock_members.Member(
          ..old,
          first_name: model.draft_first_name,
          last_name: model.draft_last_name,
          email: model.draft_email,
          date_of_birth: model.draft_dob,
          role: model.draft_role,
          is_managed: model.draft_is_managed,
        )
      let updated_mwd = MemberWithData(..model.member, member: updated_member)
      Model(..model, member: updated_mwd)
    }
  }
}

pub fn view(model: types.Model) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "bg-white rounded-lg shadow-sm border border-gray-200 p-6 mb-6",
      ),
    ],
    [
      html.h2([attribute.class("text-lg font-semibold text-gray-900 mb-4")], [
        element.text("Personal Information"),
      ]),
      html.div([attribute.class("grid grid-cols-1 sm:grid-cols-2 gap-4")], [
        views.labeled_input(
          "First Name",
          "text",
          model.draft_first_name,
          UpdateFirstName,
        ),
        views.labeled_input(
          "Last Name",
          "text",
          model.draft_last_name,
          UpdateLastName,
        ),
        views.labeled_input("Email", "email", model.draft_email, UpdateEmail),
        views.labeled_input("Date of Birth", "date", model.draft_dob, UpdateDob),
        html.div([], [
          html.label(
            [attribute.class("block text-sm font-medium text-gray-700 mb-1")],
            [element.text("Role")],
          ),
          html.select(
            [
              attribute.class(
                "w-full border border-gray-300 rounded-lg px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-transparent",
              ),
              event.on_change(fn(v) {
                case v {
                  "admin" -> UpdateRole(mock_members.Admin)
                  _ -> UpdateRole(mock_members.RegularMember)
                }
              }),
            ],
            [
              html.option(
                [
                  attribute.value("admin"),
                  attribute.selected(model.draft_role == mock_members.Admin),
                ],
                "Admin",
              ),
              html.option(
                [
                  attribute.value("member"),
                  attribute.selected(
                    model.draft_role == mock_members.RegularMember,
                  ),
                ],
                "Member",
              ),
            ],
          ),
        ]),
        html.div([attribute.class("flex items-center gap-2")], [
          html.input([
            attribute.type_("checkbox"),
            attribute.checked(model.draft_is_managed),
            event.on_check(fn(_) { ToggleManaged }),
          ]),
          html.label([attribute.class("text-sm font-medium text-gray-700")], [
            element.text("Managed (child account)"),
          ]),
        ]),
      ]),
      html.button(
        [
          attribute.class(
            "mt-4 bg-teal-600 hover:bg-teal-700 text-white font-semibold py-2 px-4 rounded-lg transition-colors",
          ),
          event.on_click(SaveCoreInfo),
        ],
        [element.text("Save")],
      ),
    ],
  )
}
