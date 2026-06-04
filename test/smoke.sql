-- pg_ai — smoke tests (no API key / no Ollama needed; structure only)
-- Run: docker compose exec -T db psql -U postgres -d pgai -v ON_ERROR_STOP=1 -f - < test/smoke.sql
\set ON_ERROR_STOP on

-- 1) thin layer present
DO $$
BEGIN
  IF (SELECT count(*) FROM pg_extension WHERE extname IN ('vector','plpython3u')) <> 2 THEN
    RAISE EXCEPTION 'base extensions missing (vector/plpython3u)';
  END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'ai') < 8 THEN
    RAISE EXCEPTION 'expected >= 8 ai.* functions';
  END IF;
  IF (SELECT count(*) FROM ai.models) < 3 THEN
    RAISE EXCEPTION 'model registry not seeded';
  END IF;
  RAISE NOTICE 'thin layer OK';
END $$;

-- 2) V2 native C extension present
CREATE EXTENSION IF NOT EXISTS pg_ai_core;

DO $$
DECLARE v text;
BEGIN
  SELECT pg_ai_core_version() INTO v;
  IF v IS NULL OR position('pg_ai_core' in v) = 0 THEN
    RAISE EXCEPTION 'pg_ai_core_version() failed: %', v;
  END IF;
  RAISE NOTICE 'pg_ai_core present: %', v;
END $$;

-- 3) planner hook counts AI-semantic queries (marker query, no Ollama call)
SELECT pg_ai_core_reset();
SELECT 1 WHERE 'x' = 'ai.embed';

DO $$
DECLARE i bigint;
BEGIN
  SELECT ai_intercepted INTO i FROM pg_ai_core_stats();
  IF i < 1 THEN
    RAISE EXCEPTION 'planner hook did not count AI query (intercepted=%)', i;
  END IF;
  RAISE NOTICE 'planner-hook telemetry OK (intercepted=%)', i;
END $$;

\echo '=== ALL SMOKE TESTS PASSED ==='
