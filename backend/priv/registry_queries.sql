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
