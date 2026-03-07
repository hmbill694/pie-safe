import envoy
import gleam/int

pub type Config {
  Config(registry_db_path: String, port: Int)
}

pub fn load() -> Config {
  let registry_db_path = case envoy.get("REGISTRY_DB_PATH") {
    Ok(v) -> v
    Error(Nil) ->
      panic as "Missing required environment variable: REGISTRY_DB_PATH"
  }

  let port_str = case envoy.get("PORT") {
    Ok(v) -> v
    Error(Nil) -> panic as "Missing required environment variable: PORT"
  }

  let port = case int.parse(port_str) {
    Ok(p) -> p
    Error(Nil) -> panic as "Invalid value for PORT: must be a valid integer"
  }

  Config(registry_db_path: registry_db_path, port: port)
}
