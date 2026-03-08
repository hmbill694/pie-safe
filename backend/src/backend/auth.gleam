import backend/config
import backend/family_db_actor
import backend/family_db_supervisor
import backend/jwt
import backend/registry_actor
import backend/sql as family_sql
import backend/token
import gleam/bit_array
import gleam/bytes_tree
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http/cookie
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import mist
import youid/uuid

pub type AuthCtx {
  AuthCtx(
    cfg: config.Config,
    registry_name: process.Name(registry_actor.Message),
    supervisor_name: process.Name(family_db_supervisor.Message),
  )
}

type TimeUnit {
  Second
}

@external(erlang, "erlang", "system_time")
fn system_time_seconds(unit: TimeUnit) -> Int

fn now_iso() -> String {
  timestamp.system_time()
  |> timestamp.to_rfc3339(calendar.utc_offset)
}

fn now_plus_15min_iso() -> String {
  timestamp.from_unix_seconds(system_time_seconds(Second) + 900)
  |> timestamp.to_rfc3339(calendar.utc_offset)
}

fn json_response(
  status: Int,
  body: String,
) -> response.Response(mist.ResponseData) {
  response.new(status)
  |> response.set_header("content-type", "application/json")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

fn json_ok() -> response.Response(mist.ResponseData) {
  json.object([#("ok", json.bool(True))])
  |> json.to_string
  |> json_response(200, _)
}

fn json_error(status: Int, msg: String) -> response.Response(mist.ResponseData) {
  json.object([#("error", json.string(msg))])
  |> json.to_string
  |> json_response(status, _)
}

fn read_body_string(
  req: request.Request(mist.Connection),
) -> Result(String, String) {
  case mist.read_body(req, 1_000_000) {
    Error(_) -> Error("failed to read request body")
    Ok(req_with_body) -> {
      case bit_array.to_string(req_with_body.body) {
        Error(_) -> Error("request body is not valid utf8")
        Ok(s) -> Ok(s)
      }
    }
  }
}

fn generate_and_store_token(
  account_id: Int,
  ctx: AuthCtx,
) -> Result(String, String) {
  let raw_token = token.generate()
  let hashed = token.hash(raw_token)
  let now = now_iso()
  let expires_at = now_plus_15min_iso()

  let registry = process.named_subject(ctx.registry_name)
  use _ <- result.try(
    process.call(registry, 5000, fn(reply_to) {
      registry_actor.InsertRegistryAuthToken(
        reply_to:,
        account_id:,
        token_hash: hashed,
        token_type: "magic_link",
        expires_at:,
        used_at: None,
        created_at: now,
      )
    }),
  )

  Ok(raw_token)
}

fn log_magic_link(raw_token: String, port: Int) -> Nil {
  io.println(
    "[magic-link] http://localhost:"
    <> int.to_string(port)
    <> "/api/auth/verify?token="
    <> raw_token,
  )
}

pub fn handle_register(
  req: request.Request(mist.Connection),
  ctx: AuthCtx,
) -> response.Response(mist.ResponseData) {
  case read_body_string(req) {
    Error(e) -> json_error(400, e)
    Ok(body_str) -> {
      let decoder = {
        use first_name <- decode.field("first_name", decode.string)
        use last_name <- decode.field("last_name", decode.string)
        use family_name <- decode.field("family_name", decode.string)
        use email <- decode.field("email", decode.string)
        decode.success(#(first_name, last_name, family_name, email))
      }
      case json.parse(from: body_str, using: decoder) {
        Error(_) -> json_error(400, "invalid request body")
        Ok(#(first_name, last_name, family_name, email)) -> {
          let registry = process.named_subject(ctx.registry_name)

          // Check email uniqueness
          case
            process.call(registry, 5000, fn(reply_to) {
              registry_actor.GetAccountByEmail(reply_to:, email:)
            })
          {
            Error(e) -> json_error(500, e)
            Ok(Some(_)) -> json_error(409, "email already registered")
            Ok(None) -> {
              let family_id = uuid.v4_string()
              let db_path = "data/" <> family_id <> ".db"
              let now = now_iso()

              // Insert family
              case
                process.call(registry, 5000, fn(reply_to) {
                  registry_actor.InsertFamily(
                    reply_to:,
                    id: family_id,
                    name: family_name,
                    db_path:,
                    status: "active",
                    created_at: now,
                  )
                })
              {
                Error(e) -> json_error(500, e)
                Ok(_) -> {
                  // Insert account
                  case
                    process.call(registry, 5000, fn(reply_to) {
                      registry_actor.InsertAccount(
                        reply_to:,
                        family_id:,
                        email:,
                        role: "admin",
                        created_at: now,
                        last_login_at: None,
                      )
                    })
                  {
                    Error(e) -> json_error(500, e)
                    Ok(_) -> {
                      // Get account to retrieve account_id
                      case
                        process.call(registry, 5000, fn(reply_to) {
                          registry_actor.GetAccountByEmail(reply_to:, email:)
                        })
                      {
                        Error(e) -> json_error(500, e)
                        Ok(None) ->
                          json_error(500, "failed to retrieve created account")
                        Ok(Some(account)) -> {
                          // Start family DB and insert member
                          let supervisor =
                            process.named_subject(ctx.supervisor_name)
                          case
                            process.call(supervisor, 10_000, fn(reply_to) {
                              family_db_supervisor.GetOrStart(
                                reply_to:,
                                family_id:,
                                registry_name: ctx.registry_name,
                              )
                            })
                          {
                            Error(e) -> json_error(500, e)
                            Ok(family_actor) -> {
                              case
                                process.call(family_actor, 5000, fn(reply_to) {
                                  family_db_actor.Exec(
                                    query: family_sql.insert_member(
                                      email: Some(email),
                                      first_name: first_name,
                                      last_name: last_name,
                                      date_of_birth: None,
                                      role: "admin",
                                      is_managed: 0,
                                      created_at: now,
                                      updated_at: now,
                                    ),
                                    reply_to:,
                                  )
                                })
                              {
                                Error(e) -> json_error(500, e)
                                Ok(_) -> {
                                  // Generate token and respond
                                  case
                                    generate_and_store_token(account.id, ctx)
                                  {
                                    Error(e) -> json_error(500, e)
                                    Ok(raw_token) -> {
                                      log_magic_link(raw_token, ctx.cfg.port)
                                      json_ok()
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

pub fn handle_magic_link(
  req: request.Request(mist.Connection),
  ctx: AuthCtx,
) -> response.Response(mist.ResponseData) {
  case read_body_string(req) {
    Error(e) -> json_error(400, e)
    Ok(body_str) -> {
      let decoder = {
        use email <- decode.field("email", decode.string)
        decode.success(email)
      }
      case json.parse(from: body_str, using: decoder) {
        Error(_) -> json_error(400, "invalid request body")
        Ok(email) -> {
          let registry = process.named_subject(ctx.registry_name)
          case
            process.call(registry, 5000, fn(reply_to) {
              registry_actor.GetAccountByEmail(reply_to:, email:)
            })
          {
            Error(e) -> json_error(500, e)
            Ok(None) -> json_error(404, "account not found")
            Ok(Some(account)) -> {
              case generate_and_store_token(account.id, ctx) {
                Error(e) -> json_error(500, e)
                Ok(raw_token) -> {
                  log_magic_link(raw_token, ctx.cfg.port)
                  json_ok()
                }
              }
            }
          }
        }
      }
    }
  }
}

pub fn handle_verify(
  req: request.Request(mist.Connection),
  ctx: AuthCtx,
) -> response.Response(mist.ResponseData) {
  // Extract ?token= from query string
  let raw_token_result = case req.query {
    None -> Error("missing token parameter")
    Some(query_str) -> {
      let segments = string.split(query_str, "&")
      let found =
        list.find_map(segments, fn(seg) {
          case string.split_once(seg, "=") {
            Ok(#("token", value)) -> Ok(value)
            _ -> Error(Nil)
          }
        })
      result.map_error(found, fn(_) { "missing token parameter" })
    }
  }

  case raw_token_result {
    Error(e) -> json_error(400, e)
    Ok(raw_token) -> {
      let hashed = token.hash(raw_token)
      let registry = process.named_subject(ctx.registry_name)

      case
        process.call(registry, 5000, fn(reply_to) {
          registry_actor.GetRegistryAuthTokenByHash(
            reply_to:,
            token_hash: hashed,
          )
        })
      {
        Error(e) -> json_error(500, e)
        Ok(None) -> json_error(400, "invalid token")
        Ok(Some(auth_token)) -> {
          // Validate unused
          case auth_token.used_at {
            Some(_) -> json_error(400, "token already used")
            None -> {
              // Validate not expired: expires_at > now
              let now = now_iso()
              case string.compare(auth_token.expires_at, now) {
                order.Lt | order.Eq -> json_error(400, "token expired")
                _ -> {
                  // Mark used
                  let used_now = now_iso()
                  case
                    process.call(registry, 5000, fn(reply_to) {
                      registry_actor.MarkRegistryAuthTokenUsed(
                        reply_to:,
                        used_at: used_now,
                        id: auth_token.id,
                      )
                    })
                  {
                    Error(e) -> json_error(500, e)
                    Ok(_) -> {
                      // Get account
                      case
                        process.call(registry, 5000, fn(reply_to) {
                          registry_actor.GetAccount(
                            reply_to:,
                            id: auth_token.account_id,
                          )
                        })
                      {
                        Error(e) -> json_error(500, e)
                        Ok(None) -> json_error(500, "account not found")
                        Ok(Some(account)) -> {
                          // Update last login
                          let login_now = now_iso()
                          let _ =
                            process.call(registry, 5000, fn(reply_to) {
                              registry_actor.UpdateAccountLastLogin(
                                reply_to:,
                                last_login_at: login_now,
                                id: account.id,
                              )
                            })

                          // Sign JWT
                          let exp =
                            system_time_seconds(Second) + 60 * 60 * 24 * 7
                          let claims =
                            jwt.Claims(
                              family_id: account.family_id,
                              account_id: account.id,
                              email: account.email,
                              role: account.role,
                              exp:,
                            )
                          let jwt_token = jwt.sign(claims, ctx.cfg.jwt_secret)

                          // Set cookie and redirect
                          let cookie_value =
                            "pie_safe_session="
                            <> jwt_token
                            <> "; HttpOnly; Path=/; SameSite=Lax"

                          response.new(302)
                          |> response.set_header("set-cookie", cookie_value)
                          |> response.set_header("location", "/home")
                          |> response.set_body(
                            mist.Bytes(bytes_tree.from_string("")),
                          )
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

pub fn handle_me(
  req: request.Request(mist.Connection),
  ctx: AuthCtx,
) -> response.Response(mist.ResponseData) {
  case request.get_header(req, "cookie") {
    Error(_) -> json_error(401, "unauthenticated")
    Ok(cookie_header) -> {
      let pairs = cookie.parse(cookie_header)
      case list.key_find(pairs, "pie_safe_session") {
        Error(_) -> json_error(401, "unauthenticated")
        Ok(jwt_token) -> {
          case jwt.verify(jwt_token, ctx.cfg.jwt_secret) {
            Error(_) -> json_error(401, "invalid session")
            Ok(claims) -> {
              json.object([
                #("email", json.string(claims.email)),
                #("role", json.string(claims.role)),
              ])
              |> json.to_string
              |> json_response(200, _)
            }
          }
        }
      }
    }
  }
}
