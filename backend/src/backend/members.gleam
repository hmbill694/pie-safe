import backend/config
import backend/db
import backend/family_db_actor
import backend/family_db_supervisor
import backend/jwt
import backend/registry_actor
import backend/sql as family_sql
import gleam/bit_array
import gleam/bytes_tree
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/http/cookie
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/time/calendar
import gleam/time/timestamp
import mist
import parrot/dev

pub type MembersCtx {
  MembersCtx(
    cfg: config.Config,
    registry_name: process.Name(registry_actor.Message),
    supervisor_name: process.Name(family_db_supervisor.Message),
  )
}

// ── Timestamp helper ──────────────────────────────────────────────────────────

fn now_iso() -> String {
  timestamp.system_time()
  |> timestamp.to_rfc3339(calendar.utc_offset)
}

// ── Response helpers ──────────────────────────────────────────────────────────

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

// ── Auth helpers ──────────────────────────────────────────────────────────────

fn verify_session(
  req: request.Request(mist.Connection),
  cfg: config.Config,
) -> Result(jwt.Claims, response.Response(mist.ResponseData)) {
  use cookie_header <- result.try(
    request.get_header(req, "cookie")
    |> result.map_error(fn(_) { json_error(401, "unauthenticated") }),
  )
  let pairs = cookie.parse(cookie_header)
  use jwt_token <- result.try(
    list.key_find(pairs, "pie_safe_session")
    |> result.map_error(fn(_) { json_error(401, "unauthenticated") }),
  )
  use claims <- result.try(
    jwt.verify(jwt_token, cfg.jwt_secret)
    |> result.map_error(fn(_) { json_error(401, "invalid session") }),
  )
  Ok(claims)
}

fn get_family_actor(
  claims: jwt.Claims,
  ctx: MembersCtx,
) -> Result(
  Subject(family_db_actor.Message),
  response.Response(mist.ResponseData),
) {
  let supervisor = process.named_subject(ctx.supervisor_name)
  process.call(supervisor, 10_000, fn(reply_to) {
    family_db_supervisor.GetOrStart(
      reply_to:,
      family_id: claims.family_id,
      registry_name: ctx.registry_name,
    )
  })
  |> result.map_error(fn(e) { json_error(500, e) })
}

fn run_query(
  actor: Subject(family_db_actor.Message),
  query: #(String, List(dev.Param), decode.Decoder(a)),
) -> Result(List(a), response.Response(mist.ResponseData)) {
  process.call(actor, 5000, fn(reply_to) {
    family_db_actor.Query(run: fn(conn) {
      let result = db.exec_query(conn, query)
      process.send(reply_to, result)
    })
  })
  |> result.map_error(fn(e) { json_error(500, e) })
}

fn run_exec(
  actor: Subject(family_db_actor.Message),
  cmd: #(String, List(dev.Param)),
) -> Result(Nil, response.Response(mist.ResponseData)) {
  process.call(actor, 5000, fn(reply_to) {
    family_db_actor.Query(run: fn(conn) {
      let result = db.exec_command2(conn, cmd)
      process.send(reply_to, result)
    })
  })
  |> result.map_error(fn(e) { json_error(500, e) })
}

fn list_first_or_404(
  rows: List(a),
  msg: String,
) -> Result(a, response.Response(mist.ResponseData)) {
  case rows {
    [head, ..] -> Ok(head)
    [] -> Error(json_error(404, msg))
  }
}

fn unwrap_response(
  r: Result(
    response.Response(mist.ResponseData),
    response.Response(mist.ResponseData),
  ),
) -> response.Response(mist.ResponseData) {
  case r {
    Ok(resp) -> resp
    Error(resp) -> resp
  }
}

// ── JSON encoders ─────────────────────────────────────────────────────────────

fn encode_member(m: family_sql.ListMembers) -> json.Json {
  json.object([
    #("id", json.int(m.id)),
    #("email", json.nullable(m.email, json.string)),
    #("first_name", json.string(m.first_name)),
    #("last_name", json.string(m.last_name)),
    #("date_of_birth", json.nullable(m.date_of_birth, json.string)),
    #("role", json.string(m.role)),
    #("is_managed", json.int(m.is_managed)),
    #("created_at", json.string(m.created_at)),
    #("updated_at", json.string(m.updated_at)),
  ])
}

fn encode_get_member(m: family_sql.GetMember) -> json.Json {
  json.object([
    #("id", json.int(m.id)),
    #("email", json.nullable(m.email, json.string)),
    #("first_name", json.string(m.first_name)),
    #("last_name", json.string(m.last_name)),
    #("date_of_birth", json.nullable(m.date_of_birth, json.string)),
    #("role", json.string(m.role)),
    #("is_managed", json.int(m.is_managed)),
    #("created_at", json.string(m.created_at)),
    #("updated_at", json.string(m.updated_at)),
  ])
}

fn encode_allergy(a: family_sql.ListAllergiesByMember) -> json.Json {
  json.object([
    #("id", json.int(a.id)),
    #("member_id", json.int(a.member_id)),
    #("allergen", json.string(a.allergen)),
    #("allergy_type", json.string(a.allergy_type)),
    #("reaction", json.nullable(a.reaction, json.string)),
    #("severity", json.string(a.severity)),
    #("diagnosed_at", json.nullable(a.diagnosed_at, json.string)),
    #("notes", json.nullable(a.notes, json.string)),
    #("created_at", json.string(a.created_at)),
    #("updated_at", json.string(a.updated_at)),
  ])
}

fn encode_member_medication(mm: family_sql.ListMedicationsByMember) -> json.Json {
  json.object([
    #("id", json.int(mm.id)),
    #("member_id", json.int(mm.member_id)),
    #("medication_id", json.int(mm.medication_id)),
    #(
      "prescribing_provider_id",
      json.nullable(mm.prescribing_provider_id, json.int),
    ),
    #("frequency", json.nullable(mm.frequency, json.string)),
    #("instructions", json.nullable(mm.instructions, json.string)),
    #("started_at", json.string(mm.started_at)),
    #("ended_at", json.nullable(mm.ended_at, json.string)),
    #("reason", json.nullable(mm.reason, json.string)),
    #("created_at", json.string(mm.created_at)),
    #("updated_at", json.string(mm.updated_at)),
  ])
}

fn encode_immunization(i: family_sql.ListImmunizationsByMember) -> json.Json {
  json.object([
    #("id", json.int(i.id)),
    #("member_id", json.int(i.member_id)),
    #("vaccine_name", json.string(i.vaccine_name)),
    #("administered_at", json.string(i.administered_at)),
    #("provider_id", json.nullable(i.provider_id, json.int)),
    #("lot_number", json.nullable(i.lot_number, json.string)),
    #("next_due_at", json.nullable(i.next_due_at, json.string)),
    #("notes", json.nullable(i.notes, json.string)),
    #("created_at", json.string(i.created_at)),
  ])
}

fn encode_insurance(mi: family_sql.ListInsuranceByMember) -> json.Json {
  json.object([
    #("id", json.int(mi.id)),
    #("member_id", json.int(mi.member_id)),
    #("insurance_plan_id", json.int(mi.insurance_plan_id)),
    #("subscriber_id", json.nullable(mi.subscriber_id, json.string)),
    #("is_primary_subscriber", json.int(mi.is_primary_subscriber)),
    #("created_at", json.string(mi.created_at)),
  ])
}

fn encode_provider_link(mp: family_sql.ListProvidersByMember) -> json.Json {
  json.object([
    #("id", json.int(mp.id)),
    #("member_id", json.int(mp.member_id)),
    #("provider_id", json.int(mp.provider_id)),
    #("is_primary", json.int(mp.is_primary)),
    #("notes", json.nullable(mp.notes, json.string)),
  ])
}

fn encode_emergency_contact(
  ec: family_sql.ListEmergencyContactsByMember,
) -> json.Json {
  json.object([
    #("id", json.int(ec.id)),
    #("member_id", json.int(ec.member_id)),
    #("name", json.string(ec.name)),
    #("relationship", json.nullable(ec.relationship, json.string)),
    #("phone", json.string(ec.phone)),
    #("email", json.nullable(ec.email, json.string)),
    #("is_primary", json.int(ec.is_primary)),
    #("notes", json.nullable(ec.notes, json.string)),
    #("created_at", json.string(ec.created_at)),
    #("updated_at", json.string(ec.updated_at)),
  ])
}

fn encode_document(d: family_sql.ListDocumentsByMember) -> json.Json {
  json.object([
    #("id", json.int(d.id)),
    #("member_id", json.nullable(d.member_id, json.int)),
    #("title", json.string(d.title)),
    #("document_type", json.string(d.document_type)),
    #("file_name", json.string(d.file_name)),
    #("file_size_bytes", json.nullable(d.file_size_bytes, json.int)),
    #("mime_type", json.nullable(d.mime_type, json.string)),
    #("storage_path", json.string(d.storage_path)),
    #("uploaded_at", json.string(d.uploaded_at)),
    #("notes", json.nullable(d.notes, json.string)),
  ])
}

// ── Members (core) handlers ───────────────────────────────────────────────────

pub fn handle_list_members(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use members <- result.try(run_query(actor, family_sql.list_members()))
    json.object([#("members", json.array(members, encode_member))])
    |> json.to_string
    |> json_response(200, _)
    |> Ok
  }
  unwrap_response(result)
}

pub fn handle_get_member(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  id: Int,
) -> response.Response(mist.ResponseData) {
  // TODO: revisit if N+1 query latency becomes a concern
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use rows <- result.try(run_query(actor, family_sql.get_member(id: id)))
    use member <- result.try(list_first_or_404(rows, "member not found"))
    use allergies <- result.try(run_query(
      actor,
      family_sql.list_allergies_by_member(member_id: id),
    ))
    use medications <- result.try(run_query(
      actor,
      family_sql.list_medications_by_member(member_id: id),
    ))
    use immunizations <- result.try(run_query(
      actor,
      family_sql.list_immunizations_by_member(member_id: id),
    ))
    use insurance <- result.try(run_query(
      actor,
      family_sql.list_insurance_by_member(member_id: id),
    ))
    use providers <- result.try(run_query(
      actor,
      family_sql.list_providers_by_member(member_id: id),
    ))
    use emergency_contacts <- result.try(run_query(
      actor,
      family_sql.list_emergency_contacts_by_member(member_id: id),
    ))
    use documents <- result.try(run_query(
      actor,
      family_sql.list_documents_by_member(member_id: Some(id)),
    ))
    json.object([
      #("member", encode_get_member(member)),
      #("allergies", json.array(allergies, encode_allergy)),
      #("medications", json.array(medications, encode_member_medication)),
      #("immunizations", json.array(immunizations, encode_immunization)),
      #("insurance", json.array(insurance, encode_insurance)),
      #("providers", json.array(providers, encode_provider_link)),
      #(
        "emergency_contacts",
        json.array(emergency_contacts, encode_emergency_contact),
      ),
      #("documents", json.array(documents, encode_document)),
    ])
    |> json.to_string
    |> json_response(200, _)
    |> Ok
  }
  unwrap_response(result)
}

pub fn handle_create_member(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use body_str <- result.try(
      read_body_string(req)
      |> result.map_error(fn(e) { json_error(400, e) }),
    )
    let decoder = {
      use first_name <- decode.field("first_name", decode.string)
      use last_name <- decode.field("last_name", decode.string)
      use email <- decode.field("email", decode.optional(decode.string))
      use date_of_birth <- decode.field(
        "date_of_birth",
        decode.optional(decode.string),
      )
      use role <- decode.field("role", decode.string)
      use is_managed <- decode.field("is_managed", decode.int)
      decode.success(#(
        first_name,
        last_name,
        email,
        date_of_birth,
        role,
        is_managed,
      ))
    }
    use #(first_name, last_name, email, date_of_birth, role, is_managed) <- result.try(
      json.parse(from: body_str, using: decoder)
      |> result.map_error(fn(_) { json_error(400, "invalid request body") }),
    )
    use _ <- result.try(run_exec(
      actor,
      family_sql.insert_member(
        email: email,
        first_name: first_name,
        last_name: last_name,
        date_of_birth: date_of_birth,
        role: role,
        is_managed: is_managed,
        created_at: now_iso(),
        updated_at: now_iso(),
      ),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

pub fn handle_update_member(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use body_str <- result.try(
      read_body_string(req)
      |> result.map_error(fn(e) { json_error(400, e) }),
    )
    let decoder = {
      use first_name <- decode.field("first_name", decode.string)
      use last_name <- decode.field("last_name", decode.string)
      use email <- decode.field("email", decode.optional(decode.string))
      use date_of_birth <- decode.field(
        "date_of_birth",
        decode.optional(decode.string),
      )
      use role <- decode.field("role", decode.string)
      use is_managed <- decode.field("is_managed", decode.int)
      decode.success(#(
        first_name,
        last_name,
        email,
        date_of_birth,
        role,
        is_managed,
      ))
    }
    use #(first_name, last_name, email, date_of_birth, role, is_managed) <- result.try(
      json.parse(from: body_str, using: decoder)
      |> result.map_error(fn(_) { json_error(400, "invalid request body") }),
    )
    use _ <- result.try(run_exec(
      actor,
      family_sql.update_member(
        email: email,
        first_name: first_name,
        last_name: last_name,
        date_of_birth: date_of_birth,
        role: role,
        is_managed: is_managed,
        updated_at: now_iso(),
        id: id,
      ),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

pub fn handle_delete_member(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use _ <- result.try(run_exec(actor, family_sql.delete_member(id: id)))
    Ok(json_ok())
  }
  unwrap_response(result)
}

// ── Allergies handlers ────────────────────────────────────────────────────────

pub fn handle_create_allergy(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  member_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use body_str <- result.try(
      read_body_string(req)
      |> result.map_error(fn(e) { json_error(400, e) }),
    )
    let decoder = {
      use allergen <- decode.field("allergen", decode.string)
      use allergy_type <- decode.field("allergy_type", decode.string)
      use reaction <- decode.field("reaction", decode.optional(decode.string))
      use severity <- decode.field("severity", decode.string)
      use diagnosed_at <- decode.field(
        "diagnosed_at",
        decode.optional(decode.string),
      )
      use notes <- decode.field("notes", decode.optional(decode.string))
      decode.success(#(
        allergen,
        allergy_type,
        reaction,
        severity,
        diagnosed_at,
        notes,
      ))
    }
    use #(allergen, allergy_type, reaction, severity, diagnosed_at, notes) <- result.try(
      json.parse(from: body_str, using: decoder)
      |> result.map_error(fn(_) { json_error(400, "invalid request body") }),
    )
    use _ <- result.try(run_exec(
      actor,
      family_sql.insert_allergy(
        member_id: member_id,
        allergen: allergen,
        allergy_type: allergy_type,
        reaction: reaction,
        severity: severity,
        diagnosed_at: diagnosed_at,
        notes: notes,
        created_at: now_iso(),
        updated_at: now_iso(),
      ),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

pub fn handle_update_allergy(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  _member_id: Int,
  allergy_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use body_str <- result.try(
      read_body_string(req)
      |> result.map_error(fn(e) { json_error(400, e) }),
    )
    let decoder = {
      use allergen <- decode.field("allergen", decode.string)
      use allergy_type <- decode.field("allergy_type", decode.string)
      use reaction <- decode.field("reaction", decode.optional(decode.string))
      use severity <- decode.field("severity", decode.string)
      use diagnosed_at <- decode.field(
        "diagnosed_at",
        decode.optional(decode.string),
      )
      use notes <- decode.field("notes", decode.optional(decode.string))
      decode.success(#(
        allergen,
        allergy_type,
        reaction,
        severity,
        diagnosed_at,
        notes,
      ))
    }
    use #(allergen, allergy_type, reaction, severity, diagnosed_at, notes) <- result.try(
      json.parse(from: body_str, using: decoder)
      |> result.map_error(fn(_) { json_error(400, "invalid request body") }),
    )
    use _ <- result.try(run_exec(
      actor,
      family_sql.update_allergy(
        allergen: allergen,
        allergy_type: allergy_type,
        reaction: reaction,
        severity: severity,
        diagnosed_at: diagnosed_at,
        notes: notes,
        updated_at: now_iso(),
        id: allergy_id,
      ),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

pub fn handle_delete_allergy(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  _member_id: Int,
  allergy_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use _ <- result.try(run_exec(
      actor,
      family_sql.delete_allergy(id: allergy_id),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

// ── Medications handlers ──────────────────────────────────────────────────────

pub fn handle_create_medication(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  member_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use body_str <- result.try(
      read_body_string(req)
      |> result.map_error(fn(e) { json_error(400, e) }),
    )
    let decoder = {
      use medication_id <- decode.field("medication_id", decode.int)
      use prescribing_provider_id <- decode.field(
        "prescribing_provider_id",
        decode.optional(decode.int),
      )
      use frequency <- decode.field("frequency", decode.optional(decode.string))
      use instructions <- decode.field(
        "instructions",
        decode.optional(decode.string),
      )
      use started_at <- decode.field("started_at", decode.string)
      use ended_at <- decode.field("ended_at", decode.optional(decode.string))
      use reason <- decode.field("reason", decode.optional(decode.string))
      decode.success(#(
        medication_id,
        prescribing_provider_id,
        frequency,
        instructions,
        started_at,
        ended_at,
        reason,
      ))
    }
    use
      #(
        medication_id,
        prescribing_provider_id,
        frequency,
        instructions,
        started_at,
        ended_at,
        reason,
      )
    <- result.try(
      json.parse(from: body_str, using: decoder)
      |> result.map_error(fn(_) { json_error(400, "invalid request body") }),
    )
    use _ <- result.try(run_exec(
      actor,
      family_sql.insert_member_medication(
        member_id: member_id,
        medication_id: medication_id,
        prescribing_provider_id: prescribing_provider_id,
        frequency: frequency,
        instructions: instructions,
        started_at: started_at,
        ended_at: ended_at,
        reason: reason,
        created_at: now_iso(),
        updated_at: now_iso(),
      ),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

pub fn handle_update_medication(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  _member_id: Int,
  med_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use body_str <- result.try(
      read_body_string(req)
      |> result.map_error(fn(e) { json_error(400, e) }),
    )
    let decoder = {
      use prescribing_provider_id <- decode.field(
        "prescribing_provider_id",
        decode.optional(decode.int),
      )
      use frequency <- decode.field("frequency", decode.optional(decode.string))
      use instructions <- decode.field(
        "instructions",
        decode.optional(decode.string),
      )
      use started_at <- decode.field("started_at", decode.string)
      use ended_at <- decode.field("ended_at", decode.optional(decode.string))
      use reason <- decode.field("reason", decode.optional(decode.string))
      decode.success(#(
        prescribing_provider_id,
        frequency,
        instructions,
        started_at,
        ended_at,
        reason,
      ))
    }
    use
      #(
        prescribing_provider_id,
        frequency,
        instructions,
        started_at,
        ended_at,
        reason,
      )
    <- result.try(
      json.parse(from: body_str, using: decoder)
      |> result.map_error(fn(_) { json_error(400, "invalid request body") }),
    )
    use _ <- result.try(run_exec(
      actor,
      family_sql.update_member_medication(
        prescribing_provider_id: prescribing_provider_id,
        frequency: frequency,
        instructions: instructions,
        started_at: started_at,
        ended_at: ended_at,
        reason: reason,
        updated_at: now_iso(),
        id: med_id,
      ),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

pub fn handle_delete_medication(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  _member_id: Int,
  med_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use _ <- result.try(run_exec(
      actor,
      family_sql.delete_member_medication(id: med_id),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

// ── Immunizations handlers ────────────────────────────────────────────────────

pub fn handle_create_immunization(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  member_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use body_str <- result.try(
      read_body_string(req)
      |> result.map_error(fn(e) { json_error(400, e) }),
    )
    let decoder = {
      use vaccine_name <- decode.field("vaccine_name", decode.string)
      use administered_at <- decode.field("administered_at", decode.string)
      use provider_id <- decode.field(
        "provider_id",
        decode.optional(decode.int),
      )
      use lot_number <- decode.field(
        "lot_number",
        decode.optional(decode.string),
      )
      use next_due_at <- decode.field(
        "next_due_at",
        decode.optional(decode.string),
      )
      use notes <- decode.field("notes", decode.optional(decode.string))
      decode.success(#(
        vaccine_name,
        administered_at,
        provider_id,
        lot_number,
        next_due_at,
        notes,
      ))
    }
    use
      #(
        vaccine_name,
        administered_at,
        provider_id,
        lot_number,
        next_due_at,
        notes,
      )
    <- result.try(
      json.parse(from: body_str, using: decoder)
      |> result.map_error(fn(_) { json_error(400, "invalid request body") }),
    )
    use _ <- result.try(run_exec(
      actor,
      family_sql.insert_immunization(
        member_id: member_id,
        vaccine_name: vaccine_name,
        administered_at: administered_at,
        provider_id: provider_id,
        lot_number: lot_number,
        next_due_at: next_due_at,
        notes: notes,
        created_at: now_iso(),
      ),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

pub fn handle_update_immunization(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  _member_id: Int,
  imm_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use body_str <- result.try(
      read_body_string(req)
      |> result.map_error(fn(e) { json_error(400, e) }),
    )
    let decoder = {
      use vaccine_name <- decode.field("vaccine_name", decode.string)
      use administered_at <- decode.field("administered_at", decode.string)
      use provider_id <- decode.field(
        "provider_id",
        decode.optional(decode.int),
      )
      use lot_number <- decode.field(
        "lot_number",
        decode.optional(decode.string),
      )
      use next_due_at <- decode.field(
        "next_due_at",
        decode.optional(decode.string),
      )
      use notes <- decode.field("notes", decode.optional(decode.string))
      decode.success(#(
        vaccine_name,
        administered_at,
        provider_id,
        lot_number,
        next_due_at,
        notes,
      ))
    }
    use
      #(
        vaccine_name,
        administered_at,
        provider_id,
        lot_number,
        next_due_at,
        notes,
      )
    <- result.try(
      json.parse(from: body_str, using: decoder)
      |> result.map_error(fn(_) { json_error(400, "invalid request body") }),
    )
    use _ <- result.try(run_exec(
      actor,
      family_sql.update_immunization(
        vaccine_name: vaccine_name,
        administered_at: administered_at,
        provider_id: provider_id,
        lot_number: lot_number,
        next_due_at: next_due_at,
        notes: notes,
        id: imm_id,
      ),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

pub fn handle_delete_immunization(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  _member_id: Int,
  imm_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use _ <- result.try(run_exec(
      actor,
      family_sql.delete_immunization(id: imm_id),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

// ── Insurance handlers ────────────────────────────────────────────────────────

pub fn handle_create_insurance(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  member_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use body_str <- result.try(
      read_body_string(req)
      |> result.map_error(fn(e) { json_error(400, e) }),
    )
    let decoder = {
      use insurance_plan_id <- decode.field("insurance_plan_id", decode.int)
      use subscriber_id <- decode.field(
        "subscriber_id",
        decode.optional(decode.string),
      )
      use is_primary_subscriber <- decode.field(
        "is_primary_subscriber",
        decode.int,
      )
      decode.success(#(insurance_plan_id, subscriber_id, is_primary_subscriber))
    }
    use #(insurance_plan_id, subscriber_id, is_primary_subscriber) <- result.try(
      json.parse(from: body_str, using: decoder)
      |> result.map_error(fn(_) { json_error(400, "invalid request body") }),
    )
    use _ <- result.try(run_exec(
      actor,
      family_sql.insert_member_insurance(
        member_id: member_id,
        insurance_plan_id: insurance_plan_id,
        subscriber_id: subscriber_id,
        is_primary_subscriber: is_primary_subscriber,
        created_at: now_iso(),
      ),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

pub fn handle_update_insurance(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  _member_id: Int,
  ins_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use body_str <- result.try(
      read_body_string(req)
      |> result.map_error(fn(e) { json_error(400, e) }),
    )
    let decoder = {
      use subscriber_id <- decode.field(
        "subscriber_id",
        decode.optional(decode.string),
      )
      use is_primary_subscriber <- decode.field(
        "is_primary_subscriber",
        decode.int,
      )
      decode.success(#(subscriber_id, is_primary_subscriber))
    }
    use #(subscriber_id, is_primary_subscriber) <- result.try(
      json.parse(from: body_str, using: decoder)
      |> result.map_error(fn(_) { json_error(400, "invalid request body") }),
    )
    use _ <- result.try(run_exec(
      actor,
      family_sql.update_member_insurance(
        subscriber_id: subscriber_id,
        is_primary_subscriber: is_primary_subscriber,
        id: ins_id,
      ),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

pub fn handle_delete_insurance(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  _member_id: Int,
  ins_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use _ <- result.try(run_exec(
      actor,
      family_sql.delete_member_insurance(id: ins_id),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

// ── Providers handlers ────────────────────────────────────────────────────────

pub fn handle_create_provider(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  member_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use body_str <- result.try(
      read_body_string(req)
      |> result.map_error(fn(e) { json_error(400, e) }),
    )
    let decoder = {
      use provider_id <- decode.field("provider_id", decode.int)
      use is_primary <- decode.field("is_primary", decode.int)
      use notes <- decode.field("notes", decode.optional(decode.string))
      decode.success(#(provider_id, is_primary, notes))
    }
    use #(provider_id, is_primary, notes) <- result.try(
      json.parse(from: body_str, using: decoder)
      |> result.map_error(fn(_) { json_error(400, "invalid request body") }),
    )
    use _ <- result.try(run_exec(
      actor,
      family_sql.insert_member_provider(
        member_id: member_id,
        provider_id: provider_id,
        is_primary: is_primary,
        notes: notes,
      ),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

pub fn handle_update_provider(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  _member_id: Int,
  prov_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use body_str <- result.try(
      read_body_string(req)
      |> result.map_error(fn(e) { json_error(400, e) }),
    )
    let decoder = {
      use is_primary <- decode.field("is_primary", decode.int)
      use notes <- decode.field("notes", decode.optional(decode.string))
      decode.success(#(is_primary, notes))
    }
    use #(is_primary, notes) <- result.try(
      json.parse(from: body_str, using: decoder)
      |> result.map_error(fn(_) { json_error(400, "invalid request body") }),
    )
    use _ <- result.try(run_exec(
      actor,
      family_sql.update_member_provider(
        is_primary: is_primary,
        notes: notes,
        id: prov_id,
      ),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

pub fn handle_delete_provider(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  _member_id: Int,
  prov_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use _ <- result.try(run_exec(
      actor,
      family_sql.delete_member_provider(id: prov_id),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

// ── Emergency contacts handlers ───────────────────────────────────────────────

pub fn handle_create_emergency_contact(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  member_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use body_str <- result.try(
      read_body_string(req)
      |> result.map_error(fn(e) { json_error(400, e) }),
    )
    let decoder = {
      use name <- decode.field("name", decode.string)
      use relationship <- decode.field(
        "relationship",
        decode.optional(decode.string),
      )
      use phone <- decode.field("phone", decode.string)
      use email <- decode.field("email", decode.optional(decode.string))
      use is_primary <- decode.field("is_primary", decode.int)
      use notes <- decode.field("notes", decode.optional(decode.string))
      decode.success(#(name, relationship, phone, email, is_primary, notes))
    }
    use #(name, relationship, phone, email, is_primary, notes) <- result.try(
      json.parse(from: body_str, using: decoder)
      |> result.map_error(fn(_) { json_error(400, "invalid request body") }),
    )
    use _ <- result.try(run_exec(
      actor,
      family_sql.insert_emergency_contact(
        member_id: member_id,
        name: name,
        relationship: relationship,
        phone: phone,
        email: email,
        is_primary: is_primary,
        notes: notes,
        created_at: now_iso(),
        updated_at: now_iso(),
      ),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

pub fn handle_update_emergency_contact(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  _member_id: Int,
  contact_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use body_str <- result.try(
      read_body_string(req)
      |> result.map_error(fn(e) { json_error(400, e) }),
    )
    let decoder = {
      use name <- decode.field("name", decode.string)
      use relationship <- decode.field(
        "relationship",
        decode.optional(decode.string),
      )
      use phone <- decode.field("phone", decode.string)
      use email <- decode.field("email", decode.optional(decode.string))
      use is_primary <- decode.field("is_primary", decode.int)
      use notes <- decode.field("notes", decode.optional(decode.string))
      decode.success(#(name, relationship, phone, email, is_primary, notes))
    }
    use #(name, relationship, phone, email, is_primary, notes) <- result.try(
      json.parse(from: body_str, using: decoder)
      |> result.map_error(fn(_) { json_error(400, "invalid request body") }),
    )
    use _ <- result.try(run_exec(
      actor,
      family_sql.update_emergency_contact(
        name: name,
        relationship: relationship,
        phone: phone,
        email: email,
        is_primary: is_primary,
        notes: notes,
        updated_at: now_iso(),
        id: contact_id,
      ),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

pub fn handle_delete_emergency_contact(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  _member_id: Int,
  contact_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use _ <- result.try(run_exec(
      actor,
      family_sql.delete_emergency_contact(id: contact_id),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

// ── Documents handlers ────────────────────────────────────────────────────────

pub fn handle_create_document(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  member_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use body_str <- result.try(
      read_body_string(req)
      |> result.map_error(fn(e) { json_error(400, e) }),
    )
    let decoder = {
      use title <- decode.field("title", decode.string)
      use document_type <- decode.field("document_type", decode.string)
      use file_name <- decode.field("file_name", decode.string)
      use file_size_bytes <- decode.field(
        "file_size_bytes",
        decode.optional(decode.int),
      )
      use mime_type <- decode.field("mime_type", decode.optional(decode.string))
      use storage_path <- decode.field("storage_path", decode.string)
      use notes <- decode.field("notes", decode.optional(decode.string))
      decode.success(#(
        title,
        document_type,
        file_name,
        file_size_bytes,
        mime_type,
        storage_path,
        notes,
      ))
    }
    use
      #(
        title,
        document_type,
        file_name,
        file_size_bytes,
        mime_type,
        storage_path,
        notes,
      )
    <- result.try(
      json.parse(from: body_str, using: decoder)
      |> result.map_error(fn(_) { json_error(400, "invalid request body") }),
    )
    use _ <- result.try(run_exec(
      actor,
      family_sql.insert_document(
        member_id: Some(member_id),
        title: title,
        document_type: document_type,
        file_name: file_name,
        file_size_bytes: file_size_bytes,
        mime_type: mime_type,
        storage_path: storage_path,
        uploaded_at: now_iso(),
        notes: notes,
      ),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

pub fn handle_update_document(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  member_id: Int,
  doc_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use body_str <- result.try(
      read_body_string(req)
      |> result.map_error(fn(e) { json_error(400, e) }),
    )
    let decoder = {
      use title <- decode.field("title", decode.string)
      use document_type <- decode.field("document_type", decode.string)
      use file_name <- decode.field("file_name", decode.string)
      use file_size_bytes <- decode.field(
        "file_size_bytes",
        decode.optional(decode.int),
      )
      use mime_type <- decode.field("mime_type", decode.optional(decode.string))
      use storage_path <- decode.field("storage_path", decode.string)
      use notes <- decode.field("notes", decode.optional(decode.string))
      decode.success(#(
        title,
        document_type,
        file_name,
        file_size_bytes,
        mime_type,
        storage_path,
        notes,
      ))
    }
    use
      #(
        title,
        document_type,
        file_name,
        file_size_bytes,
        mime_type,
        storage_path,
        notes,
      )
    <- result.try(
      json.parse(from: body_str, using: decoder)
      |> result.map_error(fn(_) { json_error(400, "invalid request body") }),
    )
    use _ <- result.try(run_exec(
      actor,
      family_sql.update_document(
        member_id: Some(member_id),
        title: title,
        document_type: document_type,
        file_name: file_name,
        file_size_bytes: file_size_bytes,
        mime_type: mime_type,
        storage_path: storage_path,
        notes: notes,
        id: doc_id,
      ),
    ))
    Ok(json_ok())
  }
  unwrap_response(result)
}

pub fn handle_delete_document(
  req: request.Request(mist.Connection),
  ctx: MembersCtx,
  _member_id: Int,
  doc_id: Int,
) -> response.Response(mist.ResponseData) {
  let result = {
    use claims <- result.try(verify_session(req, ctx.cfg))
    use actor <- result.try(get_family_actor(claims, ctx))
    use _ <- result.try(run_exec(actor, family_sql.delete_document(id: doc_id)))
    Ok(json_ok())
  }
  unwrap_response(result)
}
