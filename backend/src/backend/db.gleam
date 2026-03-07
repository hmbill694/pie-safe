import gleam/dynamic/decode
import gleam/list
import gleam/option
import gleam/result
import parrot/dev
import sqlight

/// Convert a parrot Param to a sqlight Value.
pub fn to_sqlight(param: dev.Param) -> sqlight.Value {
  case param {
    dev.ParamInt(n) -> sqlight.int(n)
    dev.ParamString(s) -> sqlight.text(s)
    dev.ParamFloat(f) -> sqlight.float(f)
    dev.ParamBool(b) -> sqlight.bool(b)
    dev.ParamBitArray(ba) -> sqlight.blob(ba)
    dev.ParamNullable(opt) ->
      case opt {
        option.Some(inner) -> to_sqlight(inner)
        option.None -> sqlight.null()
      }
    dev.ParamList(items) -> {
      // Flatten list params — sqlight doesn't have array type
      let _ = list.map(items, to_sqlight)
      sqlight.null()
    }
    dev.ParamDynamic(_) -> sqlight.null()
    dev.ParamTimestamp(_) -> sqlight.null()
    dev.ParamDate(_) -> sqlight.null()
  }
}

/// Execute a query that returns rows (`:one` or `:many`).
pub fn exec_query(
  conn: sqlight.Connection,
  query: #(String, List(dev.Param), decode.Decoder(a)),
) -> Result(List(a), String) {
  let #(sql, params, decoder) = query
  let args = list.map(params, to_sqlight)
  sqlight.query(sql, on: conn, with: args, expecting: decoder)
  |> result.map_error(fn(err) { err.message })
}

/// Execute a command that returns no rows (`:exec`).
pub fn exec_command(
  conn: sqlight.Connection,
  command: #(String, List(dev.Param), String),
) -> Result(Nil, String) {
  let #(sql, params, _) = command
  let args = list.map(params, to_sqlight)
  sqlight.query(sql, on: conn, with: args, expecting: decode.success(Nil))
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(err) { err.message })
}
