import backend/db
import backend/registry_actor
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result
import parrot/dev
import sqlight

const family_ddl = "
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS members (
  id            INTEGER PRIMARY KEY,
  email         TEXT UNIQUE,
  first_name    TEXT NOT NULL,
  last_name     TEXT NOT NULL,
  date_of_birth TEXT,
  role          TEXT NOT NULL DEFAULT 'member',
  is_managed    INTEGER NOT NULL DEFAULT 0,
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS auth_tokens (
  id          INTEGER PRIMARY KEY,
  member_id   INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  token_hash  TEXT NOT NULL,
  token_type  TEXT NOT NULL,
  expires_at  TEXT NOT NULL,
  used_at     TEXT,
  created_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS providers (
  id         INTEGER PRIMARY KEY,
  name       TEXT NOT NULL,
  specialty  TEXT,
  phone      TEXT,
  address    TEXT,
  notes      TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS member_providers (
  id          INTEGER PRIMARY KEY,
  member_id   INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  provider_id INTEGER NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  is_primary  INTEGER NOT NULL DEFAULT 0,
  notes       TEXT
);

CREATE TABLE IF NOT EXISTS appointments (
  id                INTEGER PRIMARY KEY,
  member_id         INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  provider_id       INTEGER REFERENCES providers(id) ON DELETE SET NULL,
  title             TEXT NOT NULL,
  appointment_type  TEXT NOT NULL,
  scheduled_at      TEXT NOT NULL,
  duration_minutes  INTEGER,
  location          TEXT,
  outcome_notes     TEXT,
  cost              REAL,
  insurance_covered REAL,
  is_recurring      INTEGER NOT NULL DEFAULT 0,
  recurrence_rule   TEXT,
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS appointment_reminders (
  id              INTEGER PRIMARY KEY,
  appointment_id  INTEGER NOT NULL REFERENCES appointments(id) ON DELETE CASCADE,
  remind_at       TEXT NOT NULL,
  sent_at         TEXT,
  acknowledged_at TEXT
);

CREATE TABLE IF NOT EXISTS medications (
  id         INTEGER PRIMARY KEY,
  name       TEXT NOT NULL,
  dosage     TEXT,
  unit       TEXT,
  form       TEXT,
  notes      TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS member_medications (
  id                      INTEGER PRIMARY KEY,
  member_id               INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  medication_id           INTEGER NOT NULL REFERENCES medications(id) ON DELETE RESTRICT,
  prescribing_provider_id INTEGER REFERENCES providers(id) ON DELETE SET NULL,
  frequency               TEXT,
  instructions            TEXT,
  started_at              TEXT NOT NULL,
  ended_at                TEXT,
  reason                  TEXT,
  created_at              TEXT NOT NULL,
  updated_at              TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS allergies (
  id           INTEGER PRIMARY KEY,
  member_id    INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  allergen     TEXT NOT NULL,
  allergy_type TEXT NOT NULL,
  reaction     TEXT,
  severity     TEXT NOT NULL,
  diagnosed_at TEXT,
  notes        TEXT,
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS immunizations (
  id              INTEGER PRIMARY KEY,
  member_id       INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  vaccine_name    TEXT NOT NULL,
  administered_at TEXT NOT NULL,
  provider_id     INTEGER REFERENCES providers(id) ON DELETE SET NULL,
  lot_number      TEXT,
  next_due_at     TEXT,
  notes           TEXT,
  created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS insurance_plans (
  id             INTEGER PRIMARY KEY,
  plan_name      TEXT NOT NULL,
  insurer        TEXT NOT NULL,
  plan_type      TEXT NOT NULL,
  policy_number  TEXT,
  group_number   TEXT,
  phone          TEXT,
  website        TEXT,
  effective_from TEXT,
  effective_to   TEXT,
  notes          TEXT,
  created_at     TEXT NOT NULL,
  updated_at     TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS member_insurance (
  id                    INTEGER PRIMARY KEY,
  member_id             INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  insurance_plan_id     INTEGER NOT NULL REFERENCES insurance_plans(id) ON DELETE CASCADE,
  subscriber_id         TEXT,
  is_primary_subscriber INTEGER NOT NULL DEFAULT 0,
  created_at            TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS emergency_contacts (
  id           INTEGER PRIMARY KEY,
  member_id    INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  relationship TEXT,
  phone        TEXT NOT NULL,
  email        TEXT,
  is_primary   INTEGER NOT NULL DEFAULT 0,
  notes        TEXT,
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS documents (
  id              INTEGER PRIMARY KEY,
  member_id       INTEGER REFERENCES members(id) ON DELETE SET NULL,
  title           TEXT NOT NULL,
  document_type   TEXT NOT NULL,
  file_name       TEXT NOT NULL,
  file_size_bytes INTEGER,
  mime_type       TEXT,
  storage_path    TEXT NOT NULL,
  uploaded_at     TEXT NOT NULL,
  notes           TEXT
);
"

pub type Message {
  Exec(
    query: #(String, List(dev.Param), String),
    reply_to: Subject(Result(Nil, String)),
  )
  GetLastUsedAt(reply_to: Subject(Int))
  Shutdown
}

type State {
  State(conn: sqlight.Connection, last_used_at: Int)
}

type TimeUnit {
  Millisecond
}

@external(erlang, "erlang", "monotonic_time")
fn now_ms_raw(unit: TimeUnit) -> Int

fn now_ms() -> Int {
  now_ms_raw(Millisecond)
}

pub fn start(
  family_id: String,
  registry_name: process.Name(registry_actor.Message),
) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(10_000, fn(subject) {
    use db_path <- result.try(fetch_db_path(family_id, registry_name))
    use conn <- result.try(open_db(db_path))
    use _ <- result.try(run_family_ddl(conn))
    actor.initialised(State(conn:, last_used_at: now_ms()))
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

fn fetch_db_path(
  family_id: String,
  registry_name: process.Name(registry_actor.Message),
) -> Result(String, String) {
  let registry = process.named_subject(registry_name)
  process.call(registry, 5000, fn(reply_to) {
    registry_actor.GetDbPathForFamily(reply_to:, family_id:)
  })
}

fn open_db(db_path: String) -> Result(sqlight.Connection, String) {
  sqlight.open(db_path)
  |> result.map_error(fn(err) { "Failed to open family DB: " <> err.message })
}

fn run_family_ddl(conn: sqlight.Connection) -> Result(Nil, String) {
  sqlight.exec(family_ddl, on: conn)
  |> result.map_error(fn(err) { "Failed to run family DDL: " <> err.message })
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Exec(query:, reply_to:) -> {
      let result = db.exec_command(state.conn, query)
      process.send(reply_to, result)
      actor.continue(State(..state, last_used_at: now_ms()))
    }

    GetLastUsedAt(reply_to:) -> {
      process.send(reply_to, state.last_used_at)
      actor.continue(state)
    }

    Shutdown -> {
      let _ = sqlight.close(state.conn)
      actor.stop()
    }
  }
}
