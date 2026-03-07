import backend/db
import backend/migrations
import backend/registry_actor
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result
import parrot/dev
import sqlight

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
  migrations_dir: String,
) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(10_000, fn(subject) {
    use db_path <- result.try(fetch_db_path(family_id, registry_name))
    use conn <- result.try(open_db(db_path))
    use _ <- result.try(migrations.run(conn, migrations_dir))
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
