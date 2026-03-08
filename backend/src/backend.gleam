import backend/auth
import backend/config
import backend/db_evictor
import backend/family_db_supervisor
import backend/members
import backend/registry_actor
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
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

  let ctx = auth.AuthCtx(cfg:, registry_name:, supervisor_name:)
  let members_ctx = members.MembersCtx(cfg:, registry_name:, supervisor_name:)

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

        ["api", "auth", "register"] ->
          case req.method {
            http.Post -> auth.handle_register(req, ctx)
            _ -> not_found
          }

        ["api", "auth", "magic-link"] ->
          case req.method {
            http.Post -> auth.handle_magic_link(req, ctx)
            _ -> not_found
          }

        ["api", "auth", "verify"] ->
          case req.method {
            http.Get -> auth.handle_verify(req, ctx)
            _ -> not_found
          }

        ["api", "auth", "me"] ->
          case req.method {
            http.Get -> auth.handle_me(req, ctx)
            _ -> not_found
          }

        ["api", "members"] ->
          case req.method {
            http.Get -> members.handle_list_members(req, members_ctx)
            http.Post -> members.handle_create_member(req, members_ctx)
            _ -> not_found
          }

        ["api", "members", id_str] ->
          case int.parse(id_str) {
            Error(_) -> not_found
            Ok(id) ->
              case req.method {
                http.Get -> members.handle_get_member(req, members_ctx, id)
                http.Put -> members.handle_update_member(req, members_ctx, id)
                http.Delete ->
                  members.handle_delete_member(req, members_ctx, id)
                _ -> not_found
              }
          }

        ["api", "members", id_str, "allergies"] ->
          case int.parse(id_str) {
            Error(_) -> not_found
            Ok(member_id) ->
              case req.method {
                http.Post ->
                  members.handle_create_allergy(req, members_ctx, member_id)
                _ -> not_found
              }
          }

        ["api", "members", id_str, "allergies", aid_str] ->
          case int.parse(id_str), int.parse(aid_str) {
            Ok(member_id), Ok(allergy_id) ->
              case req.method {
                http.Put ->
                  members.handle_update_allergy(
                    req,
                    members_ctx,
                    member_id,
                    allergy_id,
                  )
                http.Delete ->
                  members.handle_delete_allergy(
                    req,
                    members_ctx,
                    member_id,
                    allergy_id,
                  )
                _ -> not_found
              }
            _, _ -> not_found
          }

        ["api", "members", id_str, "medications"] ->
          case int.parse(id_str) {
            Error(_) -> not_found
            Ok(member_id) ->
              case req.method {
                http.Post ->
                  members.handle_create_medication(req, members_ctx, member_id)
                _ -> not_found
              }
          }

        ["api", "members", id_str, "medications", mid_str] ->
          case int.parse(id_str), int.parse(mid_str) {
            Ok(member_id), Ok(med_id) ->
              case req.method {
                http.Put ->
                  members.handle_update_medication(
                    req,
                    members_ctx,
                    member_id,
                    med_id,
                  )
                http.Delete ->
                  members.handle_delete_medication(
                    req,
                    members_ctx,
                    member_id,
                    med_id,
                  )
                _ -> not_found
              }
            _, _ -> not_found
          }

        ["api", "members", id_str, "immunizations"] ->
          case int.parse(id_str) {
            Error(_) -> not_found
            Ok(member_id) ->
              case req.method {
                http.Post ->
                  members.handle_create_immunization(
                    req,
                    members_ctx,
                    member_id,
                  )
                _ -> not_found
              }
          }

        ["api", "members", id_str, "immunizations", iid_str] ->
          case int.parse(id_str), int.parse(iid_str) {
            Ok(member_id), Ok(imm_id) ->
              case req.method {
                http.Put ->
                  members.handle_update_immunization(
                    req,
                    members_ctx,
                    member_id,
                    imm_id,
                  )
                http.Delete ->
                  members.handle_delete_immunization(
                    req,
                    members_ctx,
                    member_id,
                    imm_id,
                  )
                _ -> not_found
              }
            _, _ -> not_found
          }

        ["api", "members", id_str, "insurance"] ->
          case int.parse(id_str) {
            Error(_) -> not_found
            Ok(member_id) ->
              case req.method {
                http.Post ->
                  members.handle_create_insurance(req, members_ctx, member_id)
                _ -> not_found
              }
          }

        ["api", "members", id_str, "insurance", iid_str] ->
          case int.parse(id_str), int.parse(iid_str) {
            Ok(member_id), Ok(ins_id) ->
              case req.method {
                http.Put ->
                  members.handle_update_insurance(
                    req,
                    members_ctx,
                    member_id,
                    ins_id,
                  )
                http.Delete ->
                  members.handle_delete_insurance(
                    req,
                    members_ctx,
                    member_id,
                    ins_id,
                  )
                _ -> not_found
              }
            _, _ -> not_found
          }

        ["api", "members", id_str, "providers"] ->
          case int.parse(id_str) {
            Error(_) -> not_found
            Ok(member_id) ->
              case req.method {
                http.Post ->
                  members.handle_create_provider(req, members_ctx, member_id)
                _ -> not_found
              }
          }

        ["api", "members", id_str, "providers", pid_str] ->
          case int.parse(id_str), int.parse(pid_str) {
            Ok(member_id), Ok(prov_id) ->
              case req.method {
                http.Put ->
                  members.handle_update_provider(
                    req,
                    members_ctx,
                    member_id,
                    prov_id,
                  )
                http.Delete ->
                  members.handle_delete_provider(
                    req,
                    members_ctx,
                    member_id,
                    prov_id,
                  )
                _ -> not_found
              }
            _, _ -> not_found
          }

        ["api", "members", id_str, "emergency_contacts"] ->
          case int.parse(id_str) {
            Error(_) -> not_found
            Ok(member_id) ->
              case req.method {
                http.Post ->
                  members.handle_create_emergency_contact(
                    req,
                    members_ctx,
                    member_id,
                  )
                _ -> not_found
              }
          }

        ["api", "members", id_str, "emergency_contacts", cid_str] ->
          case int.parse(id_str), int.parse(cid_str) {
            Ok(member_id), Ok(contact_id) ->
              case req.method {
                http.Put ->
                  members.handle_update_emergency_contact(
                    req,
                    members_ctx,
                    member_id,
                    contact_id,
                  )
                http.Delete ->
                  members.handle_delete_emergency_contact(
                    req,
                    members_ctx,
                    member_id,
                    contact_id,
                  )
                _ -> not_found
              }
            _, _ -> not_found
          }

        ["api", "members", id_str, "documents"] ->
          case int.parse(id_str) {
            Error(_) -> not_found
            Ok(member_id) ->
              case req.method {
                http.Post ->
                  members.handle_create_document(req, members_ctx, member_id)
                _ -> not_found
              }
          }

        ["api", "members", id_str, "documents", did_str] ->
          case int.parse(id_str), int.parse(did_str) {
            Ok(member_id), Ok(doc_id) ->
              case req.method {
                http.Put ->
                  members.handle_update_document(
                    req,
                    members_ctx,
                    member_id,
                    doc_id,
                  )
                http.Delete ->
                  members.handle_delete_document(
                    req,
                    members_ctx,
                    member_id,
                    doc_id,
                  )
                _ -> not_found
              }
            _, _ -> not_found
          }

        // SPA fallback — serve index.html for all non-static routes
        // so the Lustre router can handle /sign-in, /sign-up, /home, etc.
        _ ->
          response.new(200)
          |> response.set_header("content-type", "text/html; charset=utf-8")
          |> response.set_body(mist.Bytes(bytes_tree.from_string(index_html)))
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
