import ffi/browser
import gleam/int
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
  Model(
    first_name: String,
    last_name: String,
    family_name: String,
    email: String,
    state: FormState,
  )
}

pub type Msg {
  UpdateFirstName(String)
  UpdateLastName(String)
  UpdateFamilyName(String)
  UpdateEmail(String)
  Submit
  ApiResponse(Result(Nil, lustre_http.HttpError))
}

pub fn init() -> Model {
  Model(first_name: "", last_name: "", family_name: "", email: "", state: Idle)
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UpdateFirstName(value) -> #(
      Model(..model, first_name: value),
      effect.none(),
    )
    UpdateLastName(value) -> #(Model(..model, last_name: value), effect.none())
    UpdateFamilyName(value) -> #(
      Model(..model, family_name: value),
      effect.none(),
    )
    UpdateEmail(value) -> #(Model(..model, email: value), effect.none())
    Submit -> {
      let body =
        json.object([
          #("first_name", json.string(model.first_name)),
          #("last_name", json.string(model.last_name)),
          #("family_name", json.string(model.family_name)),
          #("email", json.string(model.email)),
        ])
      #(
        Model(..model, state: Loading),
        lustre_http.post(
          browser.origin() <> "/api/auth/register",
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
        lustre_http.OtherError(code, body) ->
          "Error " <> int.to_string(code) <> ": " <> body
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
              "We've sent you a confirmation email. Please check your inbox to complete your registration.",
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
            element.text("Create your account"),
          ]),
          html.div([attribute.class("space-y-4")], [
            labeled_input(
              "First name",
              "text",
              model.first_name,
              UpdateFirstName,
            ),
            labeled_input("Last name", "text", model.last_name, UpdateLastName),
            labeled_input(
              "Family name",
              "text",
              model.family_name,
              UpdateFamilyName,
            ),
            labeled_input("Email", "email", model.email, UpdateEmail),
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
                True -> "Creating account..."
                False -> "Create account"
              }),
            ],
          ),
          html.p([attribute.class("mt-4 text-center text-sm text-gray-600")], [
            element.text("Already have an account? "),
            html.a(
              [
                attribute.href("/sign-in"),
                attribute.class("text-teal-600 hover:text-teal-700 font-medium"),
              ],
              [element.text("Sign in")],
            ),
          ]),
        ],
      ),
    ],
  )
}

fn labeled_input(
  label: String,
  input_type: String,
  value: String,
  on_input: fn(String) -> Msg,
) -> Element(Msg) {
  html.div([], [
    html.label(
      [attribute.class("block text-sm font-medium text-gray-700 mb-1")],
      [element.text(label)],
    ),
    html.input([
      attribute.type_(input_type),
      attribute.value(value),
      attribute.class(
        "w-full border border-gray-300 rounded-lg px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-transparent",
      ),
      event.on_input(on_input),
    ]),
  ])
}
