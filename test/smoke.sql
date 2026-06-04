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

-- 4) V2 fusion custom scan (no Ollama needed)
CREATE TEMP TABLE fusion_t (id int);
INSERT INTO fusion_t SELECT generate_series(1, 100);

DO $$
DECLARE
  c     bigint;
  line  text;
  found boolean := false;
BEGIN
  SET pg_ai_core.fuse = on;

  -- correctness: result via the custom scan must match the real answer
  SELECT count(*) INTO c FROM fusion_t WHERE id > 50;
  IF c <> 50 THEN
    RAISE EXCEPTION 'fusion custom scan returned wrong count: %', c;
  END IF;

  -- the planner must actually pick our node
  FOR line IN EXECUTE 'EXPLAIN SELECT count(*) FROM fusion_t WHERE id > 50' LOOP
    IF position('pg_ai_fusion' in line) > 0 THEN found := true; END IF;
  END LOOP;
  IF NOT found THEN
    RAISE EXCEPTION 'pg_ai_fusion custom scan was not chosen';
  END IF;

  SET pg_ai_core.fuse = off;
  RAISE NOTICE 'fusion custom scan OK (count=% , node chosen)', c;
END $$;

-- 5) filtered ANN search (adaptive over-fetch via iterative scan; no Ollama)
CREATE TEMP TABLE ann_t (id int, cat text, emb vector(768));
INSERT INTO ann_t
SELECT g,
       CASE WHEN g % 100 = 0 THEN 'rare' ELSE 'common' END,
       ('[' || (SELECT string_agg(random()::text, ',') FROM generate_series(1, 768)) || ']')::vector
FROM generate_series(1, 2000) g;
CREATE INDEX ON ann_t USING hnsw (emb vector_cosine_ops);

DO $$
DECLARE
  qv vector;
  n  int;
BEGIN
  qv := ('[' || (SELECT string_agg(random()::text, ',') FROM generate_series(1, 768)) || ']')::vector;
  -- ~20 'rare' rows exist; ask for 10 nearest among them. Adaptive over-fetch
  -- must keep scanning past ef_search to find 10 that pass the filter.
  SELECT count(*) INTO n
    FROM ai.filter_ann(qv, 'ann_t', 'cat', 'emb', 'cat = ''rare''', 10);
  IF n <> 10 THEN
    RAISE EXCEPTION 'filtered ANN returned % rows, expected 10', n;
  END IF;
  RAISE NOTICE 'filtered ANN over-fetch OK (% rows)', n;
END $$;

\echo '=== ALL SMOKE TESTS PASSED ==='
