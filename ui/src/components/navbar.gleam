import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub fn navbar(on_sign_out: msg) -> Element(msg) {
  html.nav(
    [
      attribute.class(
        "sticky top-0 z-10 bg-white border-b border-gray-200 shadow-sm",
      ),
    ],
    [
      html.div(
        [
          attribute.class(
            "max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between",
          ),
        ],
        [
          html.span([attribute.class("text-xl font-bold text-teal-600")], [
            element.text("Pie Safe"),
          ]),
          html.button(
            [
              attribute.class(
                "bg-gray-200 hover:bg-gray-300 text-gray-700 font-semibold py-2 px-4 rounded-lg transition-colors",
              ),
              event.on_click(on_sign_out),
            ],
            [element.text("Sign Out")],
          ),
        ],
      ),
    ],
  )
}
