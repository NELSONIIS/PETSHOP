#!/bin/sh
# Least-privilege roles: petora_owner owns the schema (migrations only); petora_app gets DML only.
set -eu
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<SQL
CREATE ROLE petora_owner LOGIN PASSWORD '${POSTGRES_OWNER_PASSWORD}';
CREATE ROLE petora_app LOGIN PASSWORD '${POSTGRES_APP_PASSWORD}';
ALTER DATABASE ${POSTGRES_DB} OWNER TO petora_owner;
ALTER SCHEMA public OWNER TO petora_owner;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO petora_app;
ALTER DEFAULT PRIVILEGES FOR ROLE petora_owner IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO petora_app;
ALTER DEFAULT PRIVILEGES FOR ROLE petora_owner IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO petora_app;
ALTER DEFAULT PRIVILEGES FOR ROLE petora_owner IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO petora_app;
ALTER ROLE petora_app SET statement_timeout = '15s';
SQL
