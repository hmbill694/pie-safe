import components/navbar
import data/mock_members.{type MemberWithData}
import ffi/browser
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre_http
import modem

pub type AuthState {
  Loading
  Authenticated(email: String)
  Unauthenticated
}

pub type Model {
  Model(
    auth_state: AuthState,
    members: List(MemberWithData),
    search_query: String,
  )
}

pub type SessionData {
  SessionData(email: String, role: String)
}

pub type Msg {
  GotSession(Result(SessionData, lustre_http.HttpError))
  SearchChanged(String)
  SignOut
  NavigateTo(String)
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(
    Model(
      auth_state: Loading,
      members: mock_members.all_members(),
      search_query: "",
    ),
    check_session_effect(),
  )
}

fn check_session_effect() -> Effect(Msg) {
  let decoder = {
    use email <- decode.field("email", decode.string)
    use role <- decode.field("role", decode.string)
    decode.success(SessionData(email:, role:))
  }
  lustre_http.get(
    browser.origin() <> "/api/auth/me",
    lustre_http.expect_json(decoder, GotSession),
  )
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    GotSession(Ok(data)) -> #(
      Model(..model, auth_state: Authenticated(email: data.email)),
      effect.none(),
    )
    GotSession(Error(_)) -> #(
      Model(..model, auth_state: Unauthenticated),
      modem.replace("/sign-in", None, None),
    )
    SearchChanged(q) -> #(Model(..model, search_query: q), effect.none())
    SignOut -> #(
      Model(..model, auth_state: Unauthenticated),
      modem.replace("/sign-in", None, None),
    )
    NavigateTo(path) -> #(model, modem.push(path, None, None))
  }
}

pub fn view(model: Model) -> Element(Msg) {
  case model.auth_state {
    Loading ->
      html.div(
        [
          attribute.class(
            "min-h-screen flex items-center justify-center bg-gray-50",
          ),
        ],
        [element.text("Loading...")],
      )
    Unauthenticated -> html.div([], [])
    Authenticated(_) -> authenticated_view(model)
  }
}

fn authenticated_view(model: Model) -> Element(Msg) {
  html.div([attribute.class("min-h-screen bg-gray-50")], [
    navbar.navbar(SignOut),
    html.main([attribute.class("max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8")], [
      search_and_add_bar(model),
      member_grid(model),
    ]),
  ])
}

fn search_and_add_bar(model: Model) -> Element(Msg) {
  html.div([attribute.class("flex items-center gap-4 mb-8")], [
    html.input([
      attribute.type_("search"),
      attribute.value(model.search_query),
      attribute.placeholder("Search members..."),
      attribute.class(
        "flex-1 border border-gray-300 rounded-lg px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-transparent",
      ),
      event.on_input(SearchChanged),
    ]),
    html.button(
      [
        attribute.class(
          "bg-teal-600 hover:bg-teal-700 text-white font-semibold py-2 px-4 rounded-lg transition-colors",
        ),
        event.on_click(NavigateTo("/members/new")),
      ],
      [element.text("Add Member")],
    ),
  ])
}

fn member_grid(model: Model) -> Element(Msg) {
  let q = string.lowercase(model.search_query)
  let filtered =
    list.filter(model.members, fn(mwd) {
      string.contains(string.lowercase(mwd.member.first_name), q)
      || string.contains(string.lowercase(mwd.member.last_name), q)
    })
  html.div(
    [attribute.class("grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4")],
    list.map(filtered, member_card),
  )
}

fn member_card(mwd: MemberWithData) -> Element(Msg) {
  let role_badge_class = case mwd.member.role {
    mock_members.Admin ->
      "text-xs font-medium px-2 py-0.5 rounded-full bg-teal-100 text-teal-700"
    mock_members.RegularMember ->
      "text-xs font-medium px-2 py-0.5 rounded-full bg-gray-100 text-gray-600"
  }
  let role_badge_text = case mwd.member.role {
    mock_members.Admin -> "Admin"
    mock_members.RegularMember -> "Member"
  }
  let managed_badge = case mwd.member.is_managed {
    True ->
      html.span(
        [
          attribute.class(
            "text-xs font-medium px-2 py-0.5 rounded-full bg-amber-100 text-amber-700",
          ),
        ],
        [element.text("Child")],
      )
    False -> element.text("")
  }
  html.div(
    [
      attribute.class(
        "bg-white rounded-lg shadow-sm border border-gray-200 p-5 flex items-center gap-4 cursor-pointer hover:shadow-md hover:border-teal-200 transition-all",
      ),
      event.on_click(NavigateTo("/members/" <> int.to_string(mwd.member.id))),
    ],
    [
      html.div(
        [
          attribute.class(
            "flex-shrink-0 w-12 h-12 rounded-full flex items-center justify-center text-white font-bold text-lg "
            <> avatar_colour(mwd.member.first_name),
          ),
        ],
        [element.text(initials(mwd.member))],
      ),
      html.div([attribute.class("flex-1 min-w-0")], [
        html.p([attribute.class("font-semibold text-gray-900 truncate")], [
          element.text(mwd.member.first_name <> " " <> mwd.member.last_name),
        ]),
        html.p([attribute.class("text-sm text-gray-500")], [
          element.text("DOB: " <> mwd.member.date_of_birth),
        ]),
        html.div([attribute.class("flex items-center gap-2 mt-1")], [
          html.span([attribute.class(role_badge_class)], [
            element.text(role_badge_text),
          ]),
          managed_badge,
        ]),
      ]),
    ],
  )
}

fn initials(member: mock_members.Member) -> String {
  let first = case string.first(member.first_name) {
    Ok(c) -> string.uppercase(c)
    Error(_) -> "?"
  }
  let last = case string.first(member.last_name) {
    Ok(c) -> string.uppercase(c)
    Error(_) -> ""
  }
  first <> last
}

fn avatar_colour(first_name: String) -> String {
  let code = case
    string.to_utf_codepoints(string.slice(first_name, 0, 1))
    |> list.first()
  {
    Ok(cp) -> string.utf_codepoint_to_int(cp)
    Error(_) -> 0
  }
  let remainder = case int.remainder(code, 8) {
    Ok(r) -> r
    Error(_) -> 0
  }
  case remainder {
    0 -> "bg-teal-500"
    1 -> "bg-indigo-500"
    2 -> "bg-amber-500"
    3 -> "bg-rose-500"
    4 -> "bg-violet-500"
    5 -> "bg-emerald-500"
    6 -> "bg-sky-500"
    7 -> "bg-orange-500"
    _ -> "bg-teal-500"
  }
}
