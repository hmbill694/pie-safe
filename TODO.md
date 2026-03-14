# Pie Safe — TODO

## Parrot / SQL codegen

- [x] **Remove registry SQL reference copies from `backend/src/sql/`** — moved `registry_queries.sql` and `registry_schema.sql` to `backend/priv/` so parrot can run cleanly against the family DB. Parrot was re-run successfully and `sql.gleam` is now fully generated.
