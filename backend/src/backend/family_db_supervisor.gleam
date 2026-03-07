import backend/family_db_actor
import backend/registry_actor
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/otp/actor
import gleam/otp/supervision

pub type Message {
  GetOrStart(
    reply_to: Subject(Result(Subject(family_db_actor.Message), String)),
    family_id: String,
    registry_name: process.Name(registry_actor.Message),
  )
  GetAllActors(
    reply_to: Subject(Dict(String, Subject(family_db_actor.Message))),
  )
  ActorDown(family_id: String)
}

type State {
  State(
    actors: Dict(String, Subject(family_db_actor.Message)),
    selector: process.Selector(Message),
  )
}

pub fn supervised(
  name: process.Name(Message),
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start(name) })
}

pub fn start(name: process.Name(Message)) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(5000, fn(subject) {
    let selector =
      process.new_selector()
      |> process.select(subject)
    actor.initialised(State(actors: dict.new(), selector:))
    |> actor.returning(subject)
    |> actor.selecting(selector)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.named(name)
  |> actor.start
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    GetOrStart(reply_to:, family_id:, registry_name:) -> {
      case dict.get(state.actors, family_id) {
        Ok(subject) -> {
          process.send(reply_to, Ok(subject))
          actor.continue(state)
        }
        Error(Nil) -> {
          case start_family_actor(family_id, registry_name) {
            Error(err) -> {
              process.send(reply_to, Error(err))
              actor.continue(state)
            }
            Ok(#(subject, pid)) -> {
              let monitor = process.monitor(pid)
              let new_actors = dict.insert(state.actors, family_id, subject)
              let new_selector =
                process.select_specific_monitor(state.selector, monitor, fn(_) {
                  ActorDown(family_id)
                })
              process.send(reply_to, Ok(subject))
              actor.continue(State(actors: new_actors, selector: new_selector))
              |> actor.with_selector(new_selector)
            }
          }
        }
      }
    }

    GetAllActors(reply_to:) -> {
      process.send(reply_to, state.actors)
      actor.continue(state)
    }

    ActorDown(family_id:) -> {
      let new_actors = dict.delete(state.actors, family_id)
      actor.continue(State(..state, actors: new_actors))
    }
  }
}

fn start_family_actor(
  family_id: String,
  registry_name: process.Name(registry_actor.Message),
) -> Result(#(Subject(family_db_actor.Message), Pid), String) {
  case family_db_actor.start(family_id, registry_name) {
    Ok(started) -> Ok(#(started.data, started.pid))
    Error(actor.InitTimeout) -> Error("Family actor init timed out")
    Error(actor.InitFailed(reason)) ->
      Error("Family actor init failed: " <> reason)
    Error(actor.InitExited(_)) -> Error("Family actor exited during init")
  }
}
