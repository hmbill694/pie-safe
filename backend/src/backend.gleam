import backend/config
import backend/db_evictor
import backend/family_db_supervisor
import backend/registry_actor
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/io
import gleam/option.{None}
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/result
import gleam/string
import mist.{type Connection, type ResponseData}

const index_html = "<!DOCTYPE html>
<html lang=\"en\">
  <head>
    <meta charset=\"UTF-8\" />
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />
    <title>pie-safe</title>
    <link rel=\"stylesheet\" href=\"/static/ui.css\" />
  </head>
  <body>
    <div id=\"app\"></div>
    <script type=\"module\" src=\"/static/ui.js\"></script>
  </body>
</html>"

pub fn main() {
  let cfg = config.load()

  let registry_name = process.new_name(prefix: "registry_actor")
  let supervisor_name = process.new_name(prefix: "family_db_supervisor")

  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(
      supervision.worker(fn() {
        registry_actor.start(
          cfg.registry_db_path,
          registry_name,
          cfg.registry_migrations_dir,
        )
      }),
    )
    |> static_supervisor.add(family_db_supervisor.supervised(
      supervisor_name,
      cfg.family_migrations_dir,
    ))
    |> static_supervisor.start

  let _evictor_pid = db_evictor.start(cfg, supervisor_name)

  let not_found =
    response.new(404)
    |> response.set_body(mist.Bytes(bytes_tree.from_string("Not found")))

  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(req) {
        [] ->
          response.new(200)
          |> response.set_header("content-type", "text/html; charset=utf-8")
          |> response.set_body(mist.Bytes(bytes_tree.from_string(index_html)))

        ["static", ..rest] -> serve_static(rest, not_found)

        _ -> not_found
      }
    }
    |> mist.new
    |> mist.port(cfg.port)
    |> mist.start

  io.println("Server running on http://localhost:" <> string.inspect(cfg.port))
  process.sleep_forever()
}

fn serve_static(
  path_parts: List(String),
  not_found: Response(ResponseData),
) -> Response(ResponseData) {
  let file_path = "priv/static/" <> string.join(path_parts, "/")

  mist.send_file(file_path, offset: 0, limit: None)
  |> result.map(fn(file) {
    let content_type = guess_content_type(file_path)
    response.new(200)
    |> response.set_header("content-type", content_type)
    |> response.set_body(file)
  })
  |> result.unwrap(not_found)
}

fn guess_content_type(path: String) -> String {
  case string.ends_with(path, ".js") {
    True -> "application/javascript"
    False ->
      case string.ends_with(path, ".css") {
        True -> "text/css"
        False -> "application/octet-stream"
      }
  }
}
