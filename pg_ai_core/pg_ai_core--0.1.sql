-- pg_ai_core 0.1 — native C planner integration pilot
-- complain if script is sourced in psql rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_ai_core" to load this file. \quit

CREATE FUNCTION pg_ai_core_version()
RETURNS text
AS '$libdir/pg_ai_core', 'pg_ai_core_version'
LANGUAGE C STRICT;
