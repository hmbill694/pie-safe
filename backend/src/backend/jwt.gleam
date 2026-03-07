import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/json
import gleam/result
import gleam/string

type TimeUnit {
  Second
}

@external(erlang, "erlang", "system_time")
fn system_time_seconds(unit: TimeUnit) -> Int

pub type Claims {
  Claims(
    family_id: String,
    account_id: Int,
    email: String,
    role: String,
    exp: Int,
  )
}

pub fn sign(claims: Claims, secret: String) -> String {
  let header_json =
    json.object([#("alg", json.string("HS256")), #("typ", json.string("JWT"))])
    |> json.to_string

  let payload_json =
    json.object([
      #("family_id", json.string(claims.family_id)),
      #("account_id", json.int(claims.account_id)),
      #("email", json.string(claims.email)),
      #("role", json.string(claims.role)),
      #("exp", json.int(claims.exp)),
    ])
    |> json.to_string

  let encoded_header =
    bit_array.from_string(header_json)
    |> bit_array.base64_url_encode(False)

  let encoded_payload =
    bit_array.from_string(payload_json)
    |> bit_array.base64_url_encode(False)

  let signing_input = encoded_header <> "." <> encoded_payload

  let sig_bits =
    crypto.hmac(
      bit_array.from_string(signing_input),
      crypto.Sha256,
      bit_array.from_string(secret),
    )

  let encoded_sig = bit_array.base64_url_encode(sig_bits, False)

  signing_input <> "." <> encoded_sig
}

pub fn verify(token: String, secret: String) -> Result(Claims, String) {
  let parts = string.split(token, ".")
  use #(part0, part1, part2) <- result.try(case parts {
    [p0, p1, p2] -> Ok(#(p0, p1, p2))
    _ -> Error("invalid token format")
  })

  let signing_input = part0 <> "." <> part1

  let computed_bits =
    crypto.hmac(
      bit_array.from_string(signing_input),
      crypto.Sha256,
      bit_array.from_string(secret),
    )

  use provided_bits <- result.try(
    bit_array.base64_url_decode(part2)
    |> result.map_error(fn(_) { "invalid signature encoding" }),
  )

  case crypto.secure_compare(computed_bits, provided_bits) {
    False -> Error("invalid signature")
    True -> {
      use payload_bits <- result.try(
        bit_array.base64_url_decode(part1)
        |> result.map_error(fn(_) { "invalid payload encoding" }),
      )

      use payload_str <- result.try(
        bit_array.to_string(payload_bits)
        |> result.map_error(fn(_) { "invalid payload utf8" }),
      )

      let claims_decoder = {
        use family_id <- decode.field("family_id", decode.string)
        use account_id <- decode.field("account_id", decode.int)
        use email <- decode.field("email", decode.string)
        use role <- decode.field("role", decode.string)
        use exp <- decode.field("exp", decode.int)
        decode.success(Claims(family_id:, account_id:, email:, role:, exp:))
      }

      use claims <- result.try(
        json.parse(from: payload_str, using: claims_decoder)
        |> result.map_error(fn(_) { "invalid payload json" }),
      )

      case claims.exp > system_time_seconds(Second) {
        False -> Error("token expired")
        True -> Ok(claims)
      }
    }
  }
}
