import backend/sql
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/io
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import mist.{type Connection, type ResponseData}
import parrot/dev
import sqlight

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
  use conn <- sqlight.with_connection("data/app.db")
  run_startup_query(conn)

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
    |> mist.port(3000)
    |> mist.start

  io.println("Server running on http://localhost:3000")
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

fn run_startup_query(conn: sqlight.Connection) -> Nil {
  let #(sql_str, with, expecting) = sql.list_greetings()
  let with = list.map(with, parrot_to_sqlight)
  let rows = sqlight.query(sql_str, on: conn, with: with, expecting: expecting)
  case rows {
    Ok(greetings) -> {
      io.println(
        "Startup DB query: found "
        <> string.inspect(list.length(greetings))
        <> " greeting(s)",
      )
    }
    Error(err) -> {
      io.println("Startup DB query error: " <> string.inspect(err))
    }
  }
}

fn parrot_to_sqlight(param: dev.Param) -> sqlight.Value {
  case param {
    dev.ParamBool(x) -> sqlight.bool(x)
    dev.ParamFloat(x) -> sqlight.float(x)
    dev.ParamInt(x) -> sqlight.int(x)
    dev.ParamString(x) -> sqlight.text(x)
    dev.ParamBitArray(x) -> sqlight.blob(x)
    dev.ParamNullable(x) -> sqlight.nullable(fn(a) { parrot_to_sqlight(a) }, x)
    dev.ParamList(_) -> panic as "sqlite does not support list params"
    dev.ParamDate(_) -> panic as "date params not supported for sqlite"
    dev.ParamTimestamp(_) ->
      panic as "timestamp params not supported for sqlite"
    dev.ParamDynamic(_) -> panic as "dynamic params not supported"
  }
}
