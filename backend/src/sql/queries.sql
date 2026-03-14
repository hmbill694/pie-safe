-- per-family database queries.
-- annotation format: -- name: queryname :many | :one | :exec
-- parameter placeholders use ? (positional), per the sqlight gleam library.

-- ============================================================
-- members
-- ============================================================

-- name: listmembers :many
SELECT
  id,
  email,
  first_name,
  last_name,
  date_of_birth,
  role,
  is_managed,
  created_at,
  updated_at
FROM
  members;

-- name: getmember :one
select id, email, first_name, last_name, date_of_birth, role, is_managed, created_at, updated_at
from members
where id = ?;

-- -- name: getmemberbyemail :one
-- select id, email, first_name, last_name, date_of_birth, role, is_managed, created_at, updated_at
-- from members
-- where email = ?;

-- -- name: insertmember :exec
-- insert into members (email, first_name, last_name, date_of_birth, role, is_managed, created_at, updated_at)
-- values (?, ?, ?, ?, ?, ?, ?, ?);

-- -- name: updatemember :exec
-- update members
-- set email = ?, first_name = ?, last_name = ?, date_of_birth = ?, role = ?, is_managed = ?, updated_at = ?
-- where id = ?;

-- -- name: deletemember :exec
-- delete from members where id = ?;

-- -- ============================================================
-- -- auth_tokens (family db — refresh tokens issued after login)
-- -- ============================================================

-- -- name: listauthtokensbymember :many
-- select id, member_id, token_hash, token_type, expires_at, used_at, created_at
-- from auth_tokens
-- where member_id = ?;

-- -- name: getauthtokenbyhash :one
-- select id, member_id, token_hash, token_type, expires_at, used_at, created_at
-- from auth_tokens
-- where token_hash = ?;

-- -- name: insertauthtoken :exec
-- insert into auth_tokens (member_id, token_hash, token_type, expires_at, used_at, created_at)
-- values (?, ?, ?, ?, ?, ?);

-- -- name: markauthtokenused :exec
-- update auth_tokens set used_at = ? where id = ?;

-- -- name: deleteauthtoken :exec
-- delete from auth_tokens where id = ?;

-- -- name: deleteexpiredauthtokens :exec
-- delete from auth_tokens where expires_at < ?;

-- -- ============================================================
-- -- providers
-- -- ============================================================

-- -- name: listproviders :many
-- select id, name, specialty, phone, address, notes, created_at, updated_at
-- from providers;

-- -- name: getprovider :one
-- select id, name, specialty, phone, address, notes, created_at, updated_at
-- from providers
-- where id = ?;

-- -- name: insertprovider :exec
-- insert into providers (name, specialty, phone, address, notes, created_at, updated_at)
-- values (?, ?, ?, ?, ?, ?, ?);

-- -- name: updateprovider :exec
-- update providers
-- set name = ?, specialty = ?, phone = ?, address = ?, notes = ?, updated_at = ?
-- where id = ?;

-- -- name: deleteprovider :exec
-- delete from providers where id = ?;

-- -- ============================================================
-- -- member_providers
-- -- ============================================================

-- -- name: listprovidersbymember :many
-- select id, member_id, provider_id, is_primary, notes
-- from member_providers
-- where member_id = ?;

-- -- name: getmemberprovider :one
-- select id, member_id, provider_id, is_primary, notes
-- from member_providers
-- where id = ?;

-- -- name: insertmemberprovider :exec
-- insert into member_providers (member_id, provider_id, is_primary, notes)
-- values (?, ?, ?, ?);

-- -- name: updatememberprovider :exec
-- update member_providers
-- set is_primary = ?, notes = ?
-- where id = ?;

-- -- name: deletememberprovider :exec
-- delete from member_providers where id = ?;

-- -- ============================================================
-- -- appointments
-- -- ============================================================

-- -- name: listappointments :many
-- select id, member_id, provider_id, title, appointment_type, scheduled_at, duration_minutes, location, outcome_notes, cost, insurance_covered, is_recurring, recurrence_rule, created_at, updated_at
-- from appointments;

-- -- name: listappointmentsbymember :many
-- select id, member_id, provider_id, title, appointment_type, scheduled_at, duration_minutes, location, outcome_notes, cost, insurance_covered, is_recurring, recurrence_rule, created_at, updated_at
-- from appointments
-- where member_id = ?;

-- -- name: listupcomingappointmentsbymember :many
-- select id, member_id, provider_id, title, appointment_type, scheduled_at, duration_minutes, location, outcome_notes, cost, insurance_covered, is_recurring, recurrence_rule, created_at, updated_at
-- from appointments
-- where member_id = ? and scheduled_at >= ?
-- order by scheduled_at asc;

-- -- name: getappointment :one
-- select id, member_id, provider_id, title, appointment_type, scheduled_at, duration_minutes, location, outcome_notes, cost, insurance_covered, is_recurring, recurrence_rule, created_at, updated_at
-- from appointments
-- where id = ?;

-- -- name: insertappointment :exec
-- insert into appointments (member_id, provider_id, title, appointment_type, scheduled_at, duration_minutes, location, outcome_notes, cost, insurance_covered, is_recurring, recurrence_rule, created_at, updated_at)
-- values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);

-- -- name: updateappointment :exec
-- update appointments
-- set provider_id = ?, title = ?, appointment_type = ?, scheduled_at = ?, duration_minutes = ?, location = ?, outcome_notes = ?, cost = ?, insurance_covered = ?, is_recurring = ?, recurrence_rule = ?, updated_at = ?
-- where id = ?;

-- -- name: deleteappointment :exec
-- delete from appointments where id = ?;

-- -- ============================================================
-- -- appointment_reminders
-- -- ============================================================

-- -- name: listremindersbyappointment :many
-- select id, appointment_id, remind_at, sent_at, acknowledged_at
-- from appointment_reminders
-- where appointment_id = ?;

-- -- name: listpendingreminders :many
-- select id, appointment_id, remind_at, sent_at, acknowledged_at
-- from appointment_reminders
-- where sent_at is null and remind_at <= ?;

-- -- name: getappointmentreminder :one
-- select id, appointment_id, remind_at, sent_at, acknowledged_at
-- from appointment_reminders
-- where id = ?;

-- -- name: insertappointmentreminder :exec
-- insert into appointment_reminders (appointment_id, remind_at, sent_at, acknowledged_at)
-- values (?, ?, ?, ?);

-- -- name: markremindersent :exec
-- update appointment_reminders set sent_at = ? where id = ?;

-- -- name: markreminderacknowledged :exec
-- update appointment_reminders set acknowledged_at = ? where id = ?;

-- -- name: deleteappointmentreminder :exec
-- delete from appointment_reminders where id = ?;

-- -- ============================================================
-- -- medications
-- -- ============================================================

-- -- name: listmedications :many
-- select id, name, dosage, unit, form, notes, created_at
-- from medications;

-- -- name: getmedication :one
-- select id, name, dosage, unit, form, notes, created_at
-- from medications
-- where id = ?;

-- -- name: insertmedication :exec
-- insert into medications (name, dosage, unit, form, notes, created_at)
-- values (?, ?, ?, ?, ?, ?);

-- -- name: updatemedication :exec
-- update medications
-- set name = ?, dosage = ?, unit = ?, form = ?, notes = ?
-- where id = ?;

-- -- name: deletemedication :exec
-- delete from medications where id = ?;

-- -- ============================================================
-- -- member_medications
-- -- ============================================================

-- -- name: listmedicationsbymember :many
-- select id, member_id, medication_id, prescribing_provider_id, frequency, instructions, started_at, ended_at, reason, created_at, updated_at
-- from member_medications
-- where member_id = ?;

-- -- name: listactivemedicationsbymember :many
-- select id, member_id, medication_id, prescribing_provider_id, frequency, instructions, started_at, ended_at, reason, created_at, updated_at
-- from member_medications
-- where member_id = ? and ended_at is null;

-- -- name: getmembermedication :one
-- select id, member_id, medication_id, prescribing_provider_id, frequency, instructions, started_at, ended_at, reason, created_at, updated_at
-- from member_medications
-- where id = ?;

-- -- name: insertmembermedication :exec
-- insert into member_medications (member_id, medication_id, prescribing_provider_id, frequency, instructions, started_at, ended_at, reason, created_at, updated_at)
-- values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);

-- -- name: updatemembermedication :exec
-- update member_medications
-- set prescribing_provider_id = ?, frequency = ?, instructions = ?, started_at = ?, ended_at = ?, reason = ?, updated_at = ?
-- where id = ?;

-- -- name: deletemembermedication :exec
-- delete from member_medications where id = ?;

-- -- ============================================================
-- -- allergies
-- -- ============================================================

-- -- name: listallergiesbymember :many
-- select id, member_id, allergen, allergy_type, reaction, severity, diagnosed_at, notes, created_at, updated_at
-- from allergies
-- where member_id = ?;

-- -- name: getallergy :one
-- select id, member_id, allergen, allergy_type, reaction, severity, diagnosed_at, notes, created_at, updated_at
-- from allergies
-- where id = ?;

-- -- name: insertallergy :exec
-- insert into allergies (member_id, allergen, allergy_type, reaction, severity, diagnosed_at, notes, created_at, updated_at)
-- values (?, ?, ?, ?, ?, ?, ?, ?, ?);

-- -- name: updateallergy :exec
-- update allergies
-- set allergen = ?, allergy_type = ?, reaction = ?, severity = ?, diagnosed_at = ?, notes = ?, updated_at = ?
-- where id = ?;

-- -- name: deleteallergy :exec
-- delete from allergies where id = ?;

-- -- ============================================================
-- -- immunizations
-- -- ============================================================

-- -- name: listimmunizationsbymember :many
-- select id, member_id, vaccine_name, administered_at, provider_id, lot_number, next_due_at, notes, created_at
-- from immunizations
-- where member_id = ?;

-- -- name: listdueimmunizations :many
-- select id, member_id, vaccine_name, administered_at, provider_id, lot_number, next_due_at, notes, created_at
-- from immunizations
-- where next_due_at is not null and next_due_at <= ?;

-- -- name: getimmunization :one
-- select id, member_id, vaccine_name, administered_at, provider_id, lot_number, next_due_at, notes, created_at
-- from immunizations
-- where id = ?;

-- -- name: insertimmunization :exec
-- insert into immunizations (member_id, vaccine_name, administered_at, provider_id, lot_number, next_due_at, notes, created_at)
-- values (?, ?, ?, ?, ?, ?, ?, ?);

-- -- name: updateimmunization :exec
-- update immunizations
-- set vaccine_name = ?, administered_at = ?, provider_id = ?, lot_number = ?, next_due_at = ?, notes = ?
-- where id = ?;

-- -- name: deleteimmunization :exec
-- delete from immunizations where id = ?;

-- -- ============================================================
-- -- insurance_plans
-- -- ============================================================

-- -- name: listinsuranceplans :many
-- select id, plan_name, insurer, plan_type, policy_number, group_number, phone, website, effective_from, effective_to, notes, created_at, updated_at
-- from insurance_plans;

-- -- name: listactiveinsuranceplans :many
-- select id, plan_name, insurer, plan_type, policy_number, group_number, phone, website, effective_from, effective_to, notes, created_at, updated_at
-- from insurance_plans
-- where effective_to is null;

-- -- name: getinsuranceplan :one
-- select id, plan_name, insurer, plan_type, policy_number, group_number, phone, website, effective_from, effective_to, notes, created_at, updated_at
-- from insurance_plans
-- where id = ?;

-- -- name: insertinsuranceplan :exec
-- insert into insurance_plans (plan_name, insurer, plan_type, policy_number, group_number, phone, website, effective_from, effective_to, notes, created_at, updated_at)
-- values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);

-- -- name: updateinsuranceplan :exec
-- update insurance_plans
-- set plan_name = ?, insurer = ?, plan_type = ?, policy_number = ?, group_number = ?, phone = ?, website = ?, effective_from = ?, effective_to = ?, notes = ?, updated_at = ?
-- where id = ?;

-- -- name: deleteinsuranceplan :exec
-- delete from insurance_plans where id = ?;

-- -- ============================================================
-- -- member_insurance
-- -- ============================================================

-- -- name: listinsurancebymember :many
-- select id, member_id, insurance_plan_id, subscriber_id, is_primary_subscriber, created_at
-- from member_insurance
-- where member_id = ?;

-- -- name: listmembersbyinsuranceplan :many
-- select id, member_id, insurance_plan_id, subscriber_id, is_primary_subscriber, created_at
-- from member_insurance
-- where insurance_plan_id = ?;

-- -- name: getmemberinsurance :one
-- select id, member_id, insurance_plan_id, subscriber_id, is_primary_subscriber, created_at
-- from member_insurance
-- where id = ?;

-- -- name: insertmemberinsurance :exec
-- insert into member_insurance (member_id, insurance_plan_id, subscriber_id, is_primary_subscriber, created_at)
-- values (?, ?, ?, ?, ?);

-- -- name: updatememberinsurance :exec
-- update member_insurance
-- set subscriber_id = ?, is_primary_subscriber = ?
-- where id = ?;

-- -- name: deletememberinsurance :exec
-- delete from member_insurance where id = ?;

-- -- ============================================================
-- -- emergency_contacts
-- -- ============================================================

-- -- name: listemergencycontactsbymember :many
-- select id, member_id, name, relationship, phone, email, is_primary, notes, created_at, updated_at
-- from emergency_contacts
-- where member_id = ?;

-- -- name: getemergencycontact :one
-- select id, member_id, name, relationship, phone, email, is_primary, notes, created_at, updated_at
-- from emergency_contacts
-- where id = ?;

-- -- name: insertemergencycontact :exec
-- insert into emergency_contacts (member_id, name, relationship, phone, email, is_primary, notes, created_at, updated_at)
-- values (?, ?, ?, ?, ?, ?, ?, ?, ?);

-- -- name: updateemergencycontact :exec
-- update emergency_contacts
-- set name = ?, relationship = ?, phone = ?, email = ?, is_primary = ?, notes = ?, updated_at = ?
-- where id = ?;

-- -- name: deleteemergencycontact :exec
-- delete from emergency_contacts where id = ?;

-- -- ============================================================
-- -- documents
-- -- ============================================================

-- -- name: listdocuments :many
-- select id, member_id, title, document_type, file_name, file_size_bytes, mime_type, storage_path, uploaded_at, notes
-- from documents;

-- -- name: listdocumentsbymember :many
-- select id, member_id, title, document_type, file_name, file_size_bytes, mime_type, storage_path, uploaded_at, notes
-- from documents
-- where member_id = ?;

-- -- name: listfamilydocuments :many
-- select id, member_id, title, document_type, file_name, file_size_bytes, mime_type, storage_path, uploaded_at, notes
-- from documents
-- where member_id is null;

-- -- name: getdocument :one
-- select id, member_id, title, document_type, file_name, file_size_bytes, mime_type, storage_path, uploaded_at, notes
-- from documents
-- where id = ?;

-- -- name: insertdocument :exec
-- insert into documents (member_id, title, document_type, file_name, file_size_bytes, mime_type, storage_path, uploaded_at, notes)
-- values (?, ?, ?, ?, ?, ?, ?, ?, ?);

-- -- name: updatedocument :exec
-- update documents
-- set member_id = ?, title = ?, document_type = ?, file_name = ?, file_size_bytes = ?, mime_type = ?, storage_path = ?, notes = ?
-- where id = ?;

-- -- name: deletedocument :exec
-- delete from documents where id = ?;
