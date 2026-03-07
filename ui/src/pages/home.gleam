import ffi/browser
import gleam/dynamic/decode
import gleam/option.{None}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre_http
import modem

pub type Model {
  Loading
  Authenticated(email: String)
  Unauthenticated
}

pub type SessionData {
  SessionData(email: String, role: String)
}

pub type Msg {
  GotSession(Result(SessionData, lustre_http.HttpError))
  SignOut
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(Loading, check_session_effect())
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
    GotSession(Ok(data)) -> #(Authenticated(email: data.email), effect.none())
    GotSession(Error(_)) -> #(
      Unauthenticated,
      modem.replace("/sign-in", None, None),
    )
    SignOut -> #(Unauthenticated, modem.replace("/sign-in", None, None))
  }
}

pub fn view(model: Model) -> Element(Msg) {
  case model {
    Loading -> html.div([], [element.text("Loading...")])
    Unauthenticated -> html.div([], [])
    Authenticated(email) ->
      html.div(
        [
          attribute.class(
            "min-h-screen flex items-center justify-center bg-gray-50",
          ),
        ],
        [
          html.div(
            [
              attribute.class(
                "bg-white rounded-lg shadow-md p-8 max-w-md w-full mx-4 text-center",
              ),
            ],
            [
              html.h1(
                [attribute.class("text-2xl font-bold text-gray-900 mb-4")],
                [element.text("Welcome to Pie Safe")],
              ),
              html.p([attribute.class("text-gray-600 mb-6")], [
                element.text(email),
              ]),
              html.button(
                [
                  attribute.class(
                    "bg-gray-200 hover:bg-gray-300 text-gray-700 font-semibold py-2 px-4 rounded-lg transition-colors",
                  ),
                  event.on_click(SignOut),
                ],
                [element.text("Sign out")],
              ),
            ],
          ),
        ],
      )
  }
}
