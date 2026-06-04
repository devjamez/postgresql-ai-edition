-- pg_ai_core 0.1.0 -> 0.2.0
-- Adds filtered-ANN fusion-candidate telemetry (read-only planner detection).
\echo Use "ALTER EXTENSION pg_ai_core UPDATE TO '0.2.0'" to load this file. \quit

CREATE FUNCTION pg_ai_core_fusion_candidates()
RETURNS bigint
AS '$libdir/pg_ai_core', 'pg_ai_core_fusion_candidates'
LANGUAGE C STRICT;

-- extend stats with the fusion-candidate counter
DROP FUNCTION IF EXISTS pg_ai_core_stats();
CREATE FUNCTION pg_ai_core_stats(
    OUT planned           bigint,
    OUT ai_intercepted    bigint,
    OUT fusion_candidates bigint
) RETURNS record
AS $$ SELECT pg_ai_core_planned(), pg_ai_core_intercepted(), pg_ai_core_fusion_candidates() $$
LANGUAGE sql;
