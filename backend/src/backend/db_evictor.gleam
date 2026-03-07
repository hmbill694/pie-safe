import backend/config
import backend/family_db_actor
import backend/family_db_supervisor
import gleam/dict
import gleam/erlang/process.{type Pid, type Subject}

type TimeUnit {
  Millisecond
}

@external(erlang, "erlang", "monotonic_time")
fn now_ms_raw(unit: TimeUnit) -> Int

fn now_ms() -> Int {
  now_ms_raw(Millisecond)
}

pub fn start(
  cfg: config.Config,
  supervisor_name: process.Name(family_db_supervisor.Message),
) -> Pid {
  let pid = process.spawn(fn() { loop(cfg, supervisor_name) })
  let _ = process.link(pid: pid)
  pid
}

fn loop(
  cfg: config.Config,
  supervisor_name: process.Name(family_db_supervisor.Message),
) -> Nil {
  process.sleep(cfg.eviction_check_interval_ms)
  let supervisor = process.named_subject(supervisor_name)
  let actors =
    process.call(supervisor, 5000, fn(reply_to) {
      family_db_supervisor.GetAllActors(reply_to:)
    })
  let now = now_ms()
  let _ =
    dict.each(actors, fn(family_id, actor_subject) {
      evict_if_idle(actor_subject, family_id, now, cfg.db_idle_ttl_ms)
    })
  loop(cfg, supervisor_name)
}

fn evict_if_idle(
  subject: Subject(family_db_actor.Message),
  _family_id: String,
  now: Int,
  idle_ttl_ms: Int,
) -> Nil {
  let last_used =
    process.call(subject, 5000, fn(reply_to) {
      family_db_actor.GetLastUsedAt(reply_to:)
    })
  let idle_ms = now - last_used
  case idle_ms > idle_ttl_ms {
    True -> process.send(subject, family_db_actor.Shutdown)
    False -> Nil
  }
}
