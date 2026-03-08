import gleam/dynamic/decode
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/svg
import lustre/event

pub fn navbar(
  email: String,
  role: String,
  dropdown_open: Bool,
  on_toggle_dropdown: msg,
  on_sign_out: msg,
) -> Element(msg) {
  let role_label = case role {
    "admin" -> "Admin"
    _ -> "Member"
  }
  let user_icon_button =
    html.button(
      [
        attribute.class(
          "relative flex items-center justify-center w-9 h-9 rounded-full bg-gray-100 hover:bg-gray-200 text-gray-600 transition-colors focus:outline-none focus:ring-2 focus:ring-teal-500",
        ),
        event.on_click(on_toggle_dropdown),
      ],
      [
        html.svg(
          [
            attribute.attribute("xmlns", "http://www.w3.org/2000/svg"),
            attribute.attribute("viewBox", "0 0 24 24"),
            attribute.attribute("fill", "currentColor"),
            attribute.class("w-5 h-5"),
          ],
          [
            svg.path([
              attribute.attribute("fill-rule", "evenodd"),
              attribute.attribute(
                "d",
                "M12 12a5 5 0 1 0 0-10 5 5 0 0 0 0 10zm-7 8a7 7 0 0 1 14 0H5z",
              ),
              attribute.attribute("clip-rule", "evenodd"),
            ]),
          ],
        ),
      ],
    )
  let overlay_div =
    html.div(
      [
        attribute.class("fixed inset-0 z-20"),
        event.on_click(on_toggle_dropdown),
      ],
      [],
    )
  let dropdown_panel_div =
    html.div(
      [
        attribute.class(
          "absolute right-0 top-full mt-2 w-56 bg-white border border-gray-200 rounded-lg shadow-lg z-30 py-2",
        ),
      ],
      [
        html.div(
          [
            attribute.class(
              "px-4 py-2 text-sm text-gray-900 font-medium truncate",
            ),
          ],
          [element.text(email)],
        ),
        html.div([attribute.class("px-4 pb-2 text-xs text-gray-500")], [
          element.text(role_label),
        ]),
        html.hr([attribute.class("border-gray-200 my-1")]),
        html.button(
          [
            attribute.class(
              "w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors",
            ),
            event.on_click(on_sign_out),
          ],
          [element.text("Sign Out")],
        ),
      ],
    )
  html.nav(
    [
      attribute.class(
        "sticky top-0 z-10 bg-white border-b border-gray-200 shadow-sm",
      ),
      event.on("keydown", {
        use key <- decode.field("key", decode.string)
        case key {
          "Escape" -> decode.success(on_toggle_dropdown)
          _ -> decode.failure(on_toggle_dropdown, "not Escape")
        }
      }),
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
          html.div([attribute.class("relative")], [
            user_icon_button,
            ..case dropdown_open {
              True -> [overlay_div, dropdown_panel_div]
              False -> []
            }
          ]),
        ],
      ),
    ],
  )
}
