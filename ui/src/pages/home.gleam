import ffi/local_storage
import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import modem

pub type Model {
  Authenticated(email: String)
  Unauthenticated
}

pub type Msg {
  GotToken(Result(String, Nil))
  SignOut
}

pub fn init() -> #(Model, Effect(Msg)) {
  let effect =
    effect.from(fn(dispatch) {
      dispatch(GotToken(local_storage.get_item("pie_safe_token")))
    })
  #(Unauthenticated, effect)
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    GotToken(Ok(token)) -> {
      case decode_email(token) {
        Ok(email) -> #(Authenticated(email), effect.none())
        Error(_) -> #(Unauthenticated, modem.replace("/sign-in", None, None))
      }
    }
    GotToken(Error(_)) -> #(
      Unauthenticated,
      modem.replace("/sign-in", None, None),
    )
    SignOut -> {
      local_storage.remove_item("pie_safe_token")
      #(Unauthenticated, modem.replace("/sign-in", None, None))
    }
  }
}

pub fn view(model: Model) -> Element(Msg) {
  case model {
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

fn decode_email(token: String) -> Result(String, Nil) {
  let parts = string.split(token, ".")
  use payload <- result.try(list.drop(parts, 1) |> list.first)
  use bytes <- result.try(bit_array.base64_url_decode(payload))
  use json_string <- result.try(bit_array.to_string(bytes))
  let email_decoder = {
    use email <- decode.field("email", decode.string)
    decode.success(email)
  }
  result.map_error(json.parse(from: json_string, using: email_decoder), fn(_) {
    Nil
  })
}
