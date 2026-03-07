# Family Hub — Database Schema Requirements

## Overview
A family health & information management app built with Gleam + SQLite (one database per family). The app allows families to centrally store and share information that is typically remembered by a single "family manager" — medications, appointments, providers, insurance, allergies, immunizations, emergency contacts, and documents.

## Architecture Decisions
- **One SQLite database per family** — complete data isolation per customer, no cross-tenant concerns, no `family_id` foreign keys needed
- **Passwordless auth** — magic links via email; sessions managed with JWTs + refresh tokens
- **Roles** — `admin` (the account creator, full control) and `member` (invited family members, limited edit rights)
- **Managed profiles** — family members who cannot log in themselves (e.g. children, elderly parents) are represented as profiles with `is_managed = true`
- **File storage** — document metadata only stored in DB; actual files stored externally (e.g. S3); referenced by `storage_path`

## Schema

### Auth & Users

#### `members`
Represents every person in the family — both app users (with login) and managed profiles (no login).

| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | |
| email | TEXT | Nullable — managed members may not have one; unique when present |
| first_name | TEXT NOT NULL | |
| last_name | TEXT NOT NULL | |
| date_of_birth | TEXT | ISO 8601 date |
| role | TEXT NOT NULL | `admin` or `member` |
| is_managed | INTEGER NOT NULL | Boolean (0/1) — true if member cannot log in |
| created_at | TEXT NOT NULL | ISO 8601 datetime |
| updated_at | TEXT NOT NULL | ISO 8601 datetime |

#### `auth_tokens`
Handles magic link tokens and refresh tokens for session management.

| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | |
| member_id | INTEGER NOT NULL | FK → members.id |
| token_hash | TEXT NOT NULL | Hashed token (never store raw) |
| token_type | TEXT NOT NULL | `magic_link` or `refresh` |
| expires_at | TEXT NOT NULL | ISO 8601 datetime |
| used_at | TEXT | Nullable — set when token is consumed |
| created_at | TEXT NOT NULL | ISO 8601 datetime |

---

### Health Providers

#### `providers`
Doctors, dentists, specialists, pharmacies, etc. Shared across family members.

| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | |
| name | TEXT NOT NULL | |
| specialty | TEXT | e.g. "Pediatrics", "Dentistry" |
| phone | TEXT | |
| address | TEXT | |
| notes | TEXT | |
| created_at | TEXT NOT NULL | ISO 8601 datetime |
| updated_at | TEXT NOT NULL | ISO 8601 datetime |

#### `member_providers`
Many-to-many: which family members see which providers.

| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | |
| member_id | INTEGER NOT NULL | FK → members.id |
| provider_id | INTEGER NOT NULL | FK → providers.id |
| is_primary | INTEGER NOT NULL | Boolean — is this the member's primary provider for this specialty |
| notes | TEXT | |

---

### Appointments

#### `appointments`
Scheduled visits with rich detail including recurrence and financial info.

| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | |
| member_id | INTEGER NOT NULL | FK → members.id |
| provider_id | INTEGER | Nullable FK → providers.id |
| title | TEXT NOT NULL | |
| appointment_type | TEXT NOT NULL | `checkup`, `followup`, `specialist`, `dental`, `other` |
| scheduled_at | TEXT NOT NULL | ISO 8601 datetime |
| duration_minutes | INTEGER | |
| location | TEXT | |
| outcome_notes | TEXT | Notes recorded after the appointment |
| cost | REAL | |
| insurance_covered | REAL | Amount covered by insurance |
| is_recurring | INTEGER NOT NULL | Boolean |
| recurrence_rule | TEXT | iCal RRULE string for recurring appointments |
| created_at | TEXT NOT NULL | ISO 8601 datetime |
| updated_at | TEXT NOT NULL | ISO 8601 datetime |

#### `appointment_reminders`
Tracks reminders for appointments including delivery and acknowledgement state.

| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | |
| appointment_id | INTEGER NOT NULL | FK → appointments.id |
| remind_at | TEXT NOT NULL | ISO 8601 datetime |
| sent_at | TEXT | Nullable — set when reminder is delivered |
| acknowledged_at | TEXT | Nullable — set when user acknowledges the reminder |

---

### Medications

#### `medications`
Master catalog of medications (reusable across members).

| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | |
| name | TEXT NOT NULL | |
| dosage | TEXT | e.g. "500" |
| unit | TEXT | e.g. "mg", "ml" |
| form | TEXT | `tablet`, `liquid`, `capsule`, `topical`, `other` |
| notes | TEXT | |
| created_at | TEXT NOT NULL | ISO 8601 datetime |

#### `member_medications`
A member's full medication history. Null `ended_at` means currently active.

| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | |
| member_id | INTEGER NOT NULL | FK → members.id |
| medication_id | INTEGER NOT NULL | FK → medications.id |
| prescribing_provider_id | INTEGER | Nullable FK → providers.id |
| frequency | TEXT | e.g. "twice daily", "as needed" |
| instructions | TEXT | |
| started_at | TEXT NOT NULL | ISO 8601 date |
| ended_at | TEXT | Nullable — null means still active |
| reason | TEXT | Why the medication was prescribed |
| created_at | TEXT NOT NULL | ISO 8601 datetime |
| updated_at | TEXT NOT NULL | ISO 8601 datetime |

---

### Allergies

#### `allergies`

| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | |
| member_id | INTEGER NOT NULL | FK → members.id |
| allergen | TEXT NOT NULL | e.g. "Penicillin", "Peanuts" |
| allergy_type | TEXT NOT NULL | `food`, `drug`, `environmental`, `other` |
| reaction | TEXT | Description of the reaction |
| severity | TEXT NOT NULL | `mild`, `moderate`, `severe` |
| diagnosed_at | TEXT | ISO 8601 date |
| notes | TEXT | |
| created_at | TEXT NOT NULL | ISO 8601 datetime |
| updated_at | TEXT NOT NULL | ISO 8601 datetime |

---

### Immunizations

#### `immunizations`

| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | |
| member_id | INTEGER NOT NULL | FK → members.id |
| vaccine_name | TEXT NOT NULL | |
| administered_at | TEXT NOT NULL | ISO 8601 date |
| provider_id | INTEGER | Nullable FK → providers.id |
| lot_number | TEXT | |
| next_due_at | TEXT | Nullable — ISO 8601 date for next dose |
| notes | TEXT | |
| created_at | TEXT NOT NULL | ISO 8601 datetime |

---

### Insurance

#### `insurance_plans`
A plan at the family level (medical, dental, vision, etc.).

| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | |
| plan_name | TEXT NOT NULL | |
| insurer | TEXT NOT NULL | Insurance company name |
| plan_type | TEXT NOT NULL | `medical`, `dental`, `vision`, `other` |
| policy_number | TEXT | |
| group_number | TEXT | |
| phone | TEXT | Member services phone |
| website | TEXT | |
| effective_from | TEXT | ISO 8601 date |
| effective_to | TEXT | Nullable — null means currently active |
| notes | TEXT | |
| created_at | TEXT NOT NULL | ISO 8601 datetime |
| updated_at | TEXT NOT NULL | ISO 8601 datetime |

#### `member_insurance`
Links family members to insurance plans they are covered under.

| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | |
| member_id | INTEGER NOT NULL | FK → members.id |
| insurance_plan_id | INTEGER NOT NULL | FK → insurance_plans.id |
| subscriber_id | TEXT | Member's ID on the insurance card |
| is_primary_subscriber | INTEGER NOT NULL | Boolean — is this member the policy holder |
| created_at | TEXT NOT NULL | ISO 8601 datetime |

---

### Emergency Contacts

#### `emergency_contacts`

| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | |
| member_id | INTEGER NOT NULL | FK → members.id |
| name | TEXT NOT NULL | |
| relationship | TEXT | e.g. "Spouse", "Parent", "Neighbor" |
| phone | TEXT NOT NULL | |
| email | TEXT | Nullable |
| is_primary | INTEGER NOT NULL | Boolean |
| notes | TEXT | |
| created_at | TEXT NOT NULL | ISO 8601 datetime |
| updated_at | TEXT NOT NULL | ISO 8601 datetime |

---

### Documents

#### `documents`
File metadata only — actual files stored externally and referenced by `storage_path`.

| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | |
| member_id | INTEGER | Nullable FK → members.id — null means family-wide document |
| title | TEXT NOT NULL | |
| document_type | TEXT NOT NULL | `lab_result`, `insurance_card`, `prescription`, `referral`, `other` |
| file_name | TEXT NOT NULL | Original file name |
| file_size_bytes | INTEGER | |
| mime_type | TEXT | |
| storage_path | TEXT NOT NULL | Path or URL to file in external storage |
| uploaded_at | TEXT NOT NULL | ISO 8601 datetime |
| notes | TEXT | |
