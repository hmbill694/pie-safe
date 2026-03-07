import ffi/browser
import gleam/json
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre_http

pub type FormState {
  Idle
  Loading
  Success
  FormError(String)
}

pub type Model {
  Model(email: String, state: FormState)
}

pub type Msg {
  UpdateEmail(String)
  Submit
  ApiResponse(Result(Nil, lustre_http.HttpError))
}

pub fn init() -> Model {
  Model(email: "", state: Idle)
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UpdateEmail(value) -> #(Model(..model, email: value), effect.none())
    Submit -> {
      let body = json.object([#("email", json.string(model.email))])
      #(
        Model(..model, state: Loading),
        lustre_http.post(
          browser.origin() <> "/api/auth/magic-link",
          body,
          lustre_http.expect_anything(ApiResponse),
        ),
      )
    }
    ApiResponse(Ok(_)) -> #(Model(..model, state: Success), effect.none())
    ApiResponse(Error(err)) -> {
      let message = case err {
        lustre_http.NetworkError ->
          "Network error. Please check your connection."
        lustre_http.NotFound -> "Service not found."
        lustre_http.Unauthorized -> "Unauthorized."
        lustre_http.InternalServerError(body) -> "Server error: " <> body
        lustre_http.BadUrl(url) -> "Bad URL: " <> url
        lustre_http.JsonError(_) -> "Unexpected response format."
        lustre_http.OtherError(_, body) -> "Error: " <> body
      }
      #(Model(..model, state: FormError(message)), effect.none())
    }
  }
}

pub fn view(model: Model) -> Element(Msg) {
  case model.state {
    Success -> success_view()
    _ -> form_view(model)
  }
}

fn success_view() -> Element(Msg) {
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
          html.h1([attribute.class("text-2xl font-bold text-gray-900 mb-4")], [
            element.text("Check your email"),
          ]),
          html.p([attribute.class("text-gray-600")], [
            element.text(
              "We've sent you a magic link. Please check your inbox to sign in.",
            ),
          ]),
        ],
      ),
    ],
  )
}

fn form_view(model: Model) -> Element(Msg) {
  let error_el = case model.state {
    FormError(msg) ->
      html.p([attribute.class("mt-4 text-sm text-rose-600")], [
        element.text(msg),
      ])
    _ -> element.text("")
  }

  let is_loading = model.state == Loading

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
            "bg-white rounded-lg shadow-md p-8 max-w-md w-full mx-4",
          ),
        ],
        [
          html.h1([attribute.class("text-2xl font-bold text-gray-900 mb-6")], [
            element.text("Sign in to Pie Safe"),
          ]),
          html.div([], [
            html.label(
              [attribute.class("block text-sm font-medium text-gray-700 mb-1")],
              [element.text("Email")],
            ),
            html.input([
              attribute.type_("email"),
              attribute.value(model.email),
              attribute.class(
                "w-full border border-gray-300 rounded-lg px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-transparent",
              ),
              event.on_input(UpdateEmail),
            ]),
          ]),
          error_el,
          html.button(
            [
              attribute.class(
                "mt-6 w-full bg-teal-600 hover:bg-teal-700 disabled:opacity-50 disabled:cursor-not-allowed text-white font-semibold py-2 px-4 rounded-lg transition-colors",
              ),
              attribute.disabled(is_loading),
              event.on_click(Submit),
            ],
            [
              element.text(case is_loading {
                True -> "Sending link..."
                False -> "Send magic link"
              }),
            ],
          ),
          html.p([attribute.class("mt-4 text-center text-sm text-gray-600")], [
            element.text("Don't have an account? "),
            html.a(
              [
                attribute.href("/sign-up"),
                attribute.class("text-teal-600 hover:text-teal-700 font-medium"),
              ],
              [element.text("Sign up")],
            ),
          ]),
        ],
      ),
    ],
  )
}
