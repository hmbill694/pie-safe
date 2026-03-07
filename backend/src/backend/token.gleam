import gleam/bit_array
import gleam/crypto
import gleam/string

/// Generate a cryptographically secure random token.
/// Returns a 64-character lowercase hex string.
pub fn generate() -> String {
  crypto.strong_random_bytes(32)
  |> bit_array.base16_encode
  |> string.lowercase
}

/// Hash a raw token with SHA-256.
/// Returns a 64-character lowercase hex string.
pub fn hash(raw: String) -> String {
  bit_array.from_string(raw)
  |> crypto.hash(crypto.Sha256, _)
  |> bit_array.base16_encode
  |> string.lowercase
}
