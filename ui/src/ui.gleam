import core/greeting.{type Greeting, Greeting}
import lustre
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub fn main() {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_flags) -> Greeting {
  Greeting(message: "Hello, World!")
}

pub type Msg {
  NoOp
}

fn update(model: Greeting, _msg: Msg) -> Greeting {
  model
}

fn view(model: Greeting) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "min-h-screen flex items-center justify-center bg-gray-50",
      ),
    ],
    [
      html.h1([attribute.class("text-4xl font-bold text-gray-900")], [
        element.text(model.message),
      ]),
    ],
  )
}
