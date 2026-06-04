-- pg_ai_core 0.1 — native C planner integration + telemetry pilot
\echo Use "CREATE EXTENSION pg_ai_core" to load this file. \quit

CREATE FUNCTION pg_ai_core_version()
RETURNS text
AS '$libdir/pg_ai_core', 'pg_ai_core_version'
LANGUAGE C STRICT;

CREATE FUNCTION pg_ai_core_planned()
RETURNS bigint
AS '$libdir/pg_ai_core', 'pg_ai_core_planned'
LANGUAGE C STRICT;

CREATE FUNCTION pg_ai_core_intercepted()
RETURNS bigint
AS '$libdir/pg_ai_core', 'pg_ai_core_intercepted'
LANGUAGE C STRICT;

CREATE FUNCTION pg_ai_core_reset()
RETURNS void
AS '$libdir/pg_ai_core', 'pg_ai_core_reset'
LANGUAGE C STRICT;

-- Convenience: both counters in one row
CREATE FUNCTION pg_ai_core_stats(OUT planned bigint, OUT ai_intercepted bigint)
RETURNS record
AS $$ SELECT pg_ai_core_planned(), pg_ai_core_intercepted() $$
LANGUAGE sql;
