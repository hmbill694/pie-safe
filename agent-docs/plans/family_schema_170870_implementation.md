# Implementation Plan: Family Schema + Registry Database

## Overview

This plan writes four SQL files:
- **`schema.sql`** — DDL for the per-family SQLite database (one per family group)
- **`queries.sql`** — CRUD queries for the per-family database
- **`registry_schema.sql`** — DDL for the central registry database (`data/registry.db`)
- **`registry_queries.sql`** — CRUD queries for the registry database

The **parrot** code generator is then run against both query files to produce typed Gleam. No Gleam source files are edited by hand.

---

## Auth Flow (Two-Database Architecture)

```
LOGIN REQUEST (email only)
         │
         ▼
  ┌─────────────────────┐
  │   registry.db       │
  │  accounts table     │──── lookup by email → family_id + db_path
  └─────────────────────┘
         │
         ▼
  Issue magic link token → stored in registry_auth_tokens
         │
  User clicks link
         │
         ▼
  Validate token in registry_auth_tokens
         │
         ▼
  Open family DB at db_path (e.g. data/<uuid>.db)
         │
         ▼
  Issue JWT  { family_id, member_id, role }
  + refresh token → stored in family DB's auth_tokens table
         │
  All subsequent requests
         │
         ▼
  JWT decoded → family_id identifies which DB file to open
             → member_id identifies the acting member within it
```

---

## Future Phase Note

Connection management for multiple family DBs should leverage the BEAM:
- Each family DB connection managed by a dedicated OTP `actor` (gen_server)
- A process registry (e.g. `gleam/otp` Registry or `:gproc`) maps `family_id → pid`
- Supervisor tree ensures crashed connections are restarted
- LRU eviction for inactive family connections to bound memory usage

---

## Step 1 — Write `backend/src/sql/schema.sql` (per-family database DDL)

- [ ] Open `backend/src/sql/schema.sql` and **replace the entire file** with the following content (the existing `greetings` table is removed):

```sql
-- Per-family SQLite database schema.
-- One instance of this database exists per family group.
-- The path to this file is stored in registry.db → families.db_path.
-- Enable foreign keys at connection time with: PRAGMA foreign_keys = ON;

-- ============================================================
-- Auth & Users
-- ============================================================

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

-- ============================================================
-- Health Providers
-- ============================================================

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

-- ============================================================
-- Appointments
-- ============================================================

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

-- ============================================================
-- Medications
-- ============================================================

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

-- ============================================================
-- Allergies
-- ============================================================

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

-- ============================================================
-- Immunizations
-- ============================================================

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

-- ============================================================
-- Insurance
-- ============================================================

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

-- ============================================================
-- Emergency Contacts
-- ============================================================

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

-- ============================================================
-- Documents
-- ============================================================

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
```

---

## Step 2 — Write `backend/src/sql/queries.sql` (per-family database queries)

- [ ] Open `backend/src/sql/queries.sql` and **replace the entire file** with the following content (the existing `ListGreetings` query is removed):

```sql
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
```

---

## Step 3 — Create `backend/src/sql/registry_schema.sql` (new file)

- [ ] **Create** the new file `backend/src/sql/registry_schema.sql` with the following content:

```sql
-- Central registry database schema.
-- Stored at: data/registry.db
-- One single instance for the entire application.
-- Maps email addresses → family groups → per-family database file paths.
-- Handles pre-login magic link token issuance before the family DB is known.
-- Enable foreign keys at connection time with: PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS families (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  db_path    TEXT NOT NULL UNIQUE,
  status     TEXT NOT NULL DEFAULT 'active',
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS accounts (
  id            INTEGER PRIMARY KEY,
  family_id     TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  email         TEXT NOT NULL UNIQUE,
  role          TEXT NOT NULL DEFAULT 'member',
  created_at    TEXT NOT NULL,
  last_login_at TEXT
);

CREATE TABLE IF NOT EXISTS registry_auth_tokens (
  id         INTEGER PRIMARY KEY,
  account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL,
  token_type TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  used_at    TEXT,
  created_at TEXT NOT NULL
);
```

---

## Step 4 — Create `backend/src/sql/registry_queries.sql` (new file)

- [ ] **Create** the new file `backend/src/sql/registry_queries.sql` with the following content:

```sql
-- Central registry database queries.
-- Annotation format: -- name: QueryName :many | :one | :exec
-- Parameter placeholders use ? (positional), per the sqlight Gleam library.

-- ============================================================
-- families
-- ============================================================

-- name: ListFamilies :many
SELECT id, name, db_path, status, created_at
FROM families;

-- name: GetFamily :one
SELECT id, name, db_path, status, created_at
FROM families
WHERE id = ?;

-- name: InsertFamily :exec
INSERT INTO families (id, name, db_path, status, created_at)
VALUES (?, ?, ?, ?, ?);

-- name: UpdateFamilyStatus :exec
UPDATE families SET status = ? WHERE id = ?;

-- name: DeleteFamily :exec
DELETE FROM families WHERE id = ?;

-- ============================================================
-- accounts
-- ============================================================

-- name: GetAccountByEmail :one
SELECT id, family_id, email, role, created_at, last_login_at
FROM accounts
WHERE email = ?;

-- name: GetAccount :one
SELECT id, family_id, email, role, created_at, last_login_at
FROM accounts
WHERE id = ?;

-- name: ListAccountsByFamily :many
SELECT id, family_id, email, role, created_at, last_login_at
FROM accounts
WHERE family_id = ?;

-- name: InsertAccount :exec
INSERT INTO accounts (family_id, email, role, created_at, last_login_at)
VALUES (?, ?, ?, ?, ?);

-- name: UpdateAccountLastLogin :exec
UPDATE accounts SET last_login_at = ? WHERE id = ?;

-- name: UpdateAccountRole :exec
UPDATE accounts SET role = ? WHERE id = ?;

-- name: DeleteAccount :exec
DELETE FROM accounts WHERE id = ?;

-- ============================================================
-- registry_auth_tokens
-- ============================================================

-- name: GetRegistryAuthTokenByHash :one
SELECT id, account_id, token_hash, token_type, expires_at, used_at, created_at
FROM registry_auth_tokens
WHERE token_hash = ?;

-- name: ListRegistryAuthTokensByAccount :many
SELECT id, account_id, token_hash, token_type, expires_at, used_at, created_at
FROM registry_auth_tokens
WHERE account_id = ?;

-- name: InsertRegistryAuthToken :exec
INSERT INTO registry_auth_tokens (account_id, token_hash, token_type, expires_at, used_at, created_at)
VALUES (?, ?, ?, ?, ?, ?);

-- name: MarkRegistryAuthTokenUsed :exec
UPDATE registry_auth_tokens SET used_at = ? WHERE id = ?;

-- name: DeleteRegistryAuthToken :exec
DELETE FROM registry_auth_tokens WHERE id = ?;

-- name: DeleteExpiredRegistryAuthTokens :exec
DELETE FROM registry_auth_tokens WHERE expires_at < ?;
```

---

## Step 5 — Verification checklist

- [ ] Every table from the requirements spec is present in `schema.sql` with `CREATE TABLE IF NOT EXISTS`
- [ ] `families`, `accounts`, and `registry_auth_tokens` are present in `registry_schema.sql`
- [ ] Every column appears in its table's `INSERT` and `SELECT` statements
- [ ] FK cascade rules are correct (CASCADE / SET NULL / RESTRICT as designed)
- [ ] All domain-specific filtered queries are present (`ListActiveMedicationsByMember`, `ListActiveInsurancePlans`, `ListUpcomingAppointmentsByMember`, `ListPendingReminders`, `ListDueImmunizations`, `ListFamilyDocuments`)
- [ ] `GetAccountByEmail` exists in `registry_queries.sql` and returns `family_id`
- [ ] Both auth token tables have `Insert`, `GetByHash`, `MarkUsed`, `Delete`, `DeleteExpired` queries
- [ ] `backend/src/backend/sql.gleam` and `backend/src/backend.gleam` are **not touched**
- [ ] All datetime/date values use `TEXT`. Booleans use `INTEGER`. Money uses `REAL`. IDs use `INTEGER PRIMARY KEY` except `families.id` which is `TEXT PRIMARY KEY` (UUID)
