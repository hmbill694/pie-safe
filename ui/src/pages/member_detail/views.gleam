import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub fn labeled_input(
  label: String,
  input_type: String,
  value: String,
  on_input: fn(String) -> msg,
) -> Element(msg) {
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

pub fn save_cancel_buttons(save_msg: msg, cancel_msg: msg) -> Element(msg) {
  html.div([attribute.class("flex gap-2 mt-3")], [
    html.button(
      [
        attribute.class(
          "bg-teal-600 hover:bg-teal-700 text-white font-semibold py-1.5 px-3 rounded-lg text-sm transition-colors",
        ),
        event.on_click(save_msg),
      ],
      [element.text("Save")],
    ),
    html.button(
      [
        attribute.class(
          "bg-gray-200 hover:bg-gray-300 text-gray-700 font-semibold py-1.5 px-3 rounded-lg text-sm transition-colors",
        ),
        event.on_click(cancel_msg),
      ],
      [element.text("Cancel")],
    ),
  ])
}

pub fn item_row_buttons(edit_msg: msg, delete_msg: msg) -> Element(msg) {
  html.div([attribute.class("flex gap-2 flex-shrink-0")], [
    html.button(
      [
        attribute.class("text-sm text-teal-600 hover:text-teal-700 font-medium"),
        event.on_click(edit_msg),
      ],
      [element.text("Edit")],
    ),
    html.button(
      [
        attribute.class("text-sm text-rose-600 hover:text-rose-700 font-medium"),
        event.on_click(delete_msg),
      ],
      [element.text("Delete")],
    ),
  ])
}

pub fn section_card(children: List(Element(msg))) -> Element(msg) {
  html.div(
    [
      attribute.class(
        "bg-white rounded-lg shadow-sm border border-gray-200 p-6",
      ),
    ],
    children,
  )
}
