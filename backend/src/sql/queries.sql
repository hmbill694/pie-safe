-- Per-family database queries.
-- Annotation format: -- name: QueryName :many | :one | :exec
-- Parameter placeholders use ? (positional), per the sqlight Gleam library.

-- ============================================================
-- members
-- ============================================================

-- name: ListMembers :many
SELECT id, email, first_name, last_name, date_of_birth, role, is_managed, created_at, updated_at
FROM members;

-- name: GetMember :one
SELECT id, email, first_name, last_name, date_of_birth, role, is_managed, created_at, updated_at
FROM members
WHERE id = ?;

-- name: GetMemberByEmail :one
SELECT id, email, first_name, last_name, date_of_birth, role, is_managed, created_at, updated_at
FROM members
WHERE email = ?;

-- name: InsertMember :exec
INSERT INTO members (email, first_name, last_name, date_of_birth, role, is_managed, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?);

-- name: UpdateMember :exec
UPDATE members
SET email = ?, first_name = ?, last_name = ?, date_of_birth = ?, role = ?, is_managed = ?, updated_at = ?
WHERE id = ?;

-- name: DeleteMember :exec
DELETE FROM members WHERE id = ?;

-- ============================================================
-- auth_tokens (family DB — refresh tokens issued after login)
-- ============================================================

-- name: ListAuthTokensByMember :many
SELECT id, member_id, token_hash, token_type, expires_at, used_at, created_at
FROM auth_tokens
WHERE member_id = ?;

-- name: GetAuthTokenByHash :one
SELECT id, member_id, token_hash, token_type, expires_at, used_at, created_at
FROM auth_tokens
WHERE token_hash = ?;

-- name: InsertAuthToken :exec
INSERT INTO auth_tokens (member_id, token_hash, token_type, expires_at, used_at, created_at)
VALUES (?, ?, ?, ?, ?, ?);

-- name: MarkAuthTokenUsed :exec
UPDATE auth_tokens SET used_at = ? WHERE id = ?;

-- name: DeleteAuthToken :exec
DELETE FROM auth_tokens WHERE id = ?;

-- name: DeleteExpiredAuthTokens :exec
DELETE FROM auth_tokens WHERE expires_at < ?;

-- ============================================================
-- providers
-- ============================================================

-- name: ListProviders :many
SELECT id, name, specialty, phone, address, notes, created_at, updated_at
FROM providers;

-- name: GetProvider :one
SELECT id, name, specialty, phone, address, notes, created_at, updated_at
FROM providers
WHERE id = ?;

-- name: InsertProvider :exec
INSERT INTO providers (name, specialty, phone, address, notes, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?);

-- name: UpdateProvider :exec
UPDATE providers
SET name = ?, specialty = ?, phone = ?, address = ?, notes = ?, updated_at = ?
WHERE id = ?;

-- name: DeleteProvider :exec
DELETE FROM providers WHERE id = ?;

-- ============================================================
-- member_providers
-- ============================================================

-- name: ListProvidersByMember :many
SELECT id, member_id, provider_id, is_primary, notes
FROM member_providers
WHERE member_id = ?;

-- name: GetMemberProvider :one
SELECT id, member_id, provider_id, is_primary, notes
FROM member_providers
WHERE id = ?;

-- name: InsertMemberProvider :exec
INSERT INTO member_providers (member_id, provider_id, is_primary, notes)
VALUES (?, ?, ?, ?);

-- name: UpdateMemberProvider :exec
UPDATE member_providers
SET is_primary = ?, notes = ?
WHERE id = ?;

-- name: DeleteMemberProvider :exec
DELETE FROM member_providers WHERE id = ?;

-- ============================================================
-- appointments
-- ============================================================

-- name: ListAppointments :many
SELECT id, member_id, provider_id, title, appointment_type, scheduled_at, duration_minutes, location, outcome_notes, cost, insurance_covered, is_recurring, recurrence_rule, created_at, updated_at
FROM appointments;

-- name: ListAppointmentsByMember :many
SELECT id, member_id, provider_id, title, appointment_type, scheduled_at, duration_minutes, location, outcome_notes, cost, insurance_covered, is_recurring, recurrence_rule, created_at, updated_at
FROM appointments
WHERE member_id = ?;

-- name: ListUpcomingAppointmentsByMember :many
SELECT id, member_id, provider_id, title, appointment_type, scheduled_at, duration_minutes, location, outcome_notes, cost, insurance_covered, is_recurring, recurrence_rule, created_at, updated_at
FROM appointments
WHERE member_id = ? AND scheduled_at >= ?
ORDER BY scheduled_at ASC;

-- name: GetAppointment :one
SELECT id, member_id, provider_id, title, appointment_type, scheduled_at, duration_minutes, location, outcome_notes, cost, insurance_covered, is_recurring, recurrence_rule, created_at, updated_at
FROM appointments
WHERE id = ?;

-- name: InsertAppointment :exec
INSERT INTO appointments (member_id, provider_id, title, appointment_type, scheduled_at, duration_minutes, location, outcome_notes, cost, insurance_covered, is_recurring, recurrence_rule, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);

-- name: UpdateAppointment :exec
UPDATE appointments
SET provider_id = ?, title = ?, appointment_type = ?, scheduled_at = ?, duration_minutes = ?, location = ?, outcome_notes = ?, cost = ?, insurance_covered = ?, is_recurring = ?, recurrence_rule = ?, updated_at = ?
WHERE id = ?;

-- name: DeleteAppointment :exec
DELETE FROM appointments WHERE id = ?;

-- ============================================================
-- appointment_reminders
-- ============================================================

-- name: ListRemindersByAppointment :many
SELECT id, appointment_id, remind_at, sent_at, acknowledged_at
FROM appointment_reminders
WHERE appointment_id = ?;

-- name: ListPendingReminders :many
SELECT id, appointment_id, remind_at, sent_at, acknowledged_at
FROM appointment_reminders
WHERE sent_at IS NULL AND remind_at <= ?;

-- name: GetAppointmentReminder :one
SELECT id, appointment_id, remind_at, sent_at, acknowledged_at
FROM appointment_reminders
WHERE id = ?;

-- name: InsertAppointmentReminder :exec
INSERT INTO appointment_reminders (appointment_id, remind_at, sent_at, acknowledged_at)
VALUES (?, ?, ?, ?);

-- name: MarkReminderSent :exec
UPDATE appointment_reminders SET sent_at = ? WHERE id = ?;

-- name: MarkReminderAcknowledged :exec
UPDATE appointment_reminders SET acknowledged_at = ? WHERE id = ?;

-- name: DeleteAppointmentReminder :exec
DELETE FROM appointment_reminders WHERE id = ?;

-- ============================================================
-- medications
-- ============================================================

-- name: ListMedications :many
SELECT id, name, dosage, unit, form, notes, created_at
FROM medications;

-- name: GetMedication :one
SELECT id, name, dosage, unit, form, notes, created_at
FROM medications
WHERE id = ?;

-- name: InsertMedication :exec
INSERT INTO medications (name, dosage, unit, form, notes, created_at)
VALUES (?, ?, ?, ?, ?, ?);

-- name: UpdateMedication :exec
UPDATE medications
SET name = ?, dosage = ?, unit = ?, form = ?, notes = ?
WHERE id = ?;

-- name: DeleteMedication :exec
DELETE FROM medications WHERE id = ?;

-- ============================================================
-- member_medications
-- ============================================================

-- name: ListMedicationsByMember :many
SELECT id, member_id, medication_id, prescribing_provider_id, frequency, instructions, started_at, ended_at, reason, created_at, updated_at
FROM member_medications
WHERE member_id = ?;

-- name: ListActiveMedicationsByMember :many
SELECT id, member_id, medication_id, prescribing_provider_id, frequency, instructions, started_at, ended_at, reason, created_at, updated_at
FROM member_medications
WHERE member_id = ? AND ended_at IS NULL;

-- name: GetMemberMedication :one
SELECT id, member_id, medication_id, prescribing_provider_id, frequency, instructions, started_at, ended_at, reason, created_at, updated_at
FROM member_medications
WHERE id = ?;

-- name: InsertMemberMedication :exec
INSERT INTO member_medications (member_id, medication_id, prescribing_provider_id, frequency, instructions, started_at, ended_at, reason, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);

-- name: UpdateMemberMedication :exec
UPDATE member_medications
SET prescribing_provider_id = ?, frequency = ?, instructions = ?, started_at = ?, ended_at = ?, reason = ?, updated_at = ?
WHERE id = ?;

-- name: DeleteMemberMedication :exec
DELETE FROM member_medications WHERE id = ?;

-- ============================================================
-- allergies
-- ============================================================

-- name: ListAllergiesByMember :many
SELECT id, member_id, allergen, allergy_type, reaction, severity, diagnosed_at, notes, created_at, updated_at
FROM allergies
WHERE member_id = ?;

-- name: GetAllergy :one
SELECT id, member_id, allergen, allergy_type, reaction, severity, diagnosed_at, notes, created_at, updated_at
FROM allergies
WHERE id = ?;

-- name: InsertAllergy :exec
INSERT INTO allergies (member_id, allergen, allergy_type, reaction, severity, diagnosed_at, notes, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);

-- name: UpdateAllergy :exec
UPDATE allergies
SET allergen = ?, allergy_type = ?, reaction = ?, severity = ?, diagnosed_at = ?, notes = ?, updated_at = ?
WHERE id = ?;

-- name: DeleteAllergy :exec
DELETE FROM allergies WHERE id = ?;

-- ============================================================
-- immunizations
-- ============================================================

-- name: ListImmunizationsByMember :many
SELECT id, member_id, vaccine_name, administered_at, provider_id, lot_number, next_due_at, notes, created_at
FROM immunizations
WHERE member_id = ?;

-- name: ListDueImmunizations :many
SELECT id, member_id, vaccine_name, administered_at, provider_id, lot_number, next_due_at, notes, created_at
FROM immunizations
WHERE next_due_at IS NOT NULL AND next_due_at <= ?;

-- name: GetImmunization :one
SELECT id, member_id, vaccine_name, administered_at, provider_id, lot_number, next_due_at, notes, created_at
FROM immunizations
WHERE id = ?;

-- name: InsertImmunization :exec
INSERT INTO immunizations (member_id, vaccine_name, administered_at, provider_id, lot_number, next_due_at, notes, created_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?);

-- name: UpdateImmunization :exec
UPDATE immunizations
SET vaccine_name = ?, administered_at = ?, provider_id = ?, lot_number = ?, next_due_at = ?, notes = ?
WHERE id = ?;

-- name: DeleteImmunization :exec
DELETE FROM immunizations WHERE id = ?;

-- ============================================================
-- insurance_plans
-- ============================================================

-- name: ListInsurancePlans :many
SELECT id, plan_name, insurer, plan_type, policy_number, group_number, phone, website, effective_from, effective_to, notes, created_at, updated_at
FROM insurance_plans;

-- name: ListActiveInsurancePlans :many
SELECT id, plan_name, insurer, plan_type, policy_number, group_number, phone, website, effective_from, effective_to, notes, created_at, updated_at
FROM insurance_plans
WHERE effective_to IS NULL;

-- name: GetInsurancePlan :one
SELECT id, plan_name, insurer, plan_type, policy_number, group_number, phone, website, effective_from, effective_to, notes, created_at, updated_at
FROM insurance_plans
WHERE id = ?;

-- name: InsertInsurancePlan :exec
INSERT INTO insurance_plans (plan_name, insurer, plan_type, policy_number, group_number, phone, website, effective_from, effective_to, notes, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);

-- name: UpdateInsurancePlan :exec
UPDATE insurance_plans
SET plan_name = ?, insurer = ?, plan_type = ?, policy_number = ?, group_number = ?, phone = ?, website = ?, effective_from = ?, effective_to = ?, notes = ?, updated_at = ?
WHERE id = ?;

-- name: DeleteInsurancePlan :exec
DELETE FROM insurance_plans WHERE id = ?;

-- ============================================================
-- member_insurance
-- ============================================================

-- name: ListInsuranceByMember :many
SELECT id, member_id, insurance_plan_id, subscriber_id, is_primary_subscriber, created_at
FROM member_insurance
WHERE member_id = ?;

-- name: ListMembersByInsurancePlan :many
SELECT id, member_id, insurance_plan_id, subscriber_id, is_primary_subscriber, created_at
FROM member_insurance
WHERE insurance_plan_id = ?;

-- name: GetMemberInsurance :one
SELECT id, member_id, insurance_plan_id, subscriber_id, is_primary_subscriber, created_at
FROM member_insurance
WHERE id = ?;

-- name: InsertMemberInsurance :exec
INSERT INTO member_insurance (member_id, insurance_plan_id, subscriber_id, is_primary_subscriber, created_at)
VALUES (?, ?, ?, ?, ?);

-- name: UpdateMemberInsurance :exec
UPDATE member_insurance
SET subscriber_id = ?, is_primary_subscriber = ?
WHERE id = ?;

-- name: DeleteMemberInsurance :exec
DELETE FROM member_insurance WHERE id = ?;

-- ============================================================
-- emergency_contacts
-- ============================================================

-- name: ListEmergencyContactsByMember :many
SELECT id, member_id, name, relationship, phone, email, is_primary, notes, created_at, updated_at
FROM emergency_contacts
WHERE member_id = ?;

-- name: GetEmergencyContact :one
SELECT id, member_id, name, relationship, phone, email, is_primary, notes, created_at, updated_at
FROM emergency_contacts
WHERE id = ?;

-- name: InsertEmergencyContact :exec
INSERT INTO emergency_contacts (member_id, name, relationship, phone, email, is_primary, notes, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);

-- name: UpdateEmergencyContact :exec
UPDATE emergency_contacts
SET name = ?, relationship = ?, phone = ?, email = ?, is_primary = ?, notes = ?, updated_at = ?
WHERE id = ?;

-- name: DeleteEmergencyContact :exec
DELETE FROM emergency_contacts WHERE id = ?;

-- ============================================================
-- documents
-- ============================================================

-- name: ListDocuments :many
SELECT id, member_id, title, document_type, file_name, file_size_bytes, mime_type, storage_path, uploaded_at, notes
FROM documents;

-- name: ListDocumentsByMember :many
SELECT id, member_id, title, document_type, file_name, file_size_bytes, mime_type, storage_path, uploaded_at, notes
FROM documents
WHERE member_id = ?;

-- name: ListFamilyDocuments :many
SELECT id, member_id, title, document_type, file_name, file_size_bytes, mime_type, storage_path, uploaded_at, notes
FROM documents
WHERE member_id IS NULL;

-- name: GetDocument :one
SELECT id, member_id, title, document_type, file_name, file_size_bytes, mime_type, storage_path, uploaded_at, notes
FROM documents
WHERE id = ?;

-- name: InsertDocument :exec
INSERT INTO documents (member_id, title, document_type, file_name, file_size_bytes, mime_type, storage_path, uploaded_at, notes)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);

-- name: UpdateDocument :exec
UPDATE documents
SET member_id = ?, title = ?, document_type = ?, file_name = ?, file_size_bytes = ?, mime_type = ?, storage_path = ?, notes = ?
WHERE id = ?;

-- name: DeleteDocument :exec
DELETE FROM documents WHERE id = ?;
