import envoy
import gleam/int

pub type Config {
  Config(
    registry_db_path: String,
    registry_migrations_dir: String,
    family_migrations_dir: String,
    port: Int,
    db_idle_ttl_ms: Int,
    eviction_check_interval_ms: Int,
  )
}

pub fn load() -> Config {
  let registry_db_path = case envoy.get("REGISTRY_DB_PATH") {
    Ok(v) -> v
    Error(Nil) ->
      panic as "Missing required environment variable: REGISTRY_DB_PATH"
  }

  let registry_migrations_dir = case envoy.get("REGISTRY_MIGRATIONS_DIR") {
    Ok(v) -> v
    Error(Nil) ->
      panic as "Missing required environment variable: REGISTRY_MIGRATIONS_DIR"
  }

  let family_migrations_dir = case envoy.get("FAMILY_MIGRATIONS_DIR") {
    Ok(v) -> v
    Error(Nil) ->
      panic as "Missing required environment variable: FAMILY_MIGRATIONS_DIR"
  }

  let port_str = case envoy.get("PORT") {
    Ok(v) -> v
    Error(Nil) -> panic as "Missing required environment variable: PORT"
  }

  let port = case int.parse(port_str) {
    Ok(p) -> p
    Error(Nil) -> panic as "Invalid value for PORT: must be a valid integer"
  }

  let db_idle_ttl_ms = load_optional_int("DB_IDLE_TTL_MS", 300_000)
  let eviction_check_interval_ms =
    load_optional_int("EVICTION_CHECK_INTERVAL_MS", 60_000)

  Config(
    registry_db_path:,
    registry_migrations_dir:,
    family_migrations_dir:,
    port:,
    db_idle_ttl_ms:,
    eviction_check_interval_ms:,
  )
}

fn load_optional_int(var: String, default: Int) -> Int {
  case envoy.get(var) {
    Ok(v) ->
      case int.parse(v) {
        Ok(n) -> n
        Error(Nil) -> default
      }
    Error(Nil) -> default
  }
}
