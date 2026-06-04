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
    FROM ai.filter_ann(qv, 'ann_t', 'cat', 'emb', '{"cat": "rare"}'::jsonb, 10);
  IF n <> 10 THEN
    RAISE EXCEPTION 'filtered ANN returned % rows, expected 10', n;
  END IF;
  RAISE NOTICE 'filtered ANN over-fetch OK (% rows)', n;
END $$;

-- 5b) fusion-candidate detection (planner saw the filter+vector+limit pattern)
DO $$
DECLARE f bigint;
BEGIN
  SELECT fusion_candidates INTO f FROM pg_ai_core_stats();
  IF f < 1 THEN
    RAISE EXCEPTION 'fusion-candidate detection did not fire (%)', f;
  END IF;
  RAISE NOTICE 'fusion-candidate detection OK (%)', f;
END $$;

-- 6) RBAC: powerful (network / raw-SQL) functions are revoked from PUBLIC
DO $$
BEGIN
  IF has_function_privilege('public', 'ai.embed(text)', 'execute') THEN
    RAISE EXCEPTION 'ai.embed must not be executable by PUBLIC';
  END IF;
  IF has_function_privilege('public', 'ai.filter_ann_raw(vector,regclass,text,text,text,int)', 'execute') THEN
    RAISE EXCEPTION 'ai.filter_ann_raw must not be executable by PUBLIC';
  END IF;
  IF NOT has_function_privilege('public', 'ai.similarity(vector,vector)', 'execute') THEN
    RAISE EXCEPTION 'ai.similarity should be executable by PUBLIC';
  END IF;
  RAISE NOTICE 'RBAC deny-by-default OK';
END $$;

-- 7) chunking + MMR rerank (no Ollama; MMR reuses the ann_t fixture)
DO $$
DECLARE
  nchunks int;
  qv      vector;
  nres    int;
BEGIN
  SELECT count(*) INTO nchunks FROM ai.chunk(repeat('x', 1000), 200, 20);
  IF nchunks < 5 THEN
    RAISE EXCEPTION 'chunk produced too few windows: %', nchunks;
  END IF;

  qv := ('[' || (SELECT string_agg(random()::text, ',') FROM generate_series(1,768)) || ']')::vector;
  SELECT count(*) INTO nres FROM ai.search_mmr(qv, 'ann_t', 'cat', 'emb', 5, 20, 0.5);
  IF nres <> 5 THEN
    RAISE EXCEPTION 'search_mmr returned % rows, expected 5', nres;
  END IF;
  RAISE NOTICE 'chunk + MMR OK (chunks=%, mmr_rows=%)', nchunks, nres;
END $$;

-- 8) M2 auto-apply (opt-in): transparent iterative scan, transaction-local (no leak)
SET pg_ai_core.auto_fuse = on;
SET enable_seqscan = off;
SET enable_bitmapscan = off;
DO $$
DECLARE qv vector; n int;
BEGIN
  qv := (SELECT emb FROM ann_t LIMIT 1);
  -- forced index + iterative OFF would under-return; auto_fuse must enable it -> full 10
  SELECT count(*) INTO n FROM (SELECT 1 FROM ann_t WHERE cat = 'rare' ORDER BY emb <=> qv LIMIT 10) s;
  IF n <> 10 THEN
    RAISE EXCEPTION 'auto_fuse transparent enable failed (got % of 10)', n;
  END IF;
  RAISE NOTICE 'auto_fuse transparent OK (% rows)', n;
END $$;

SET enable_seqscan = on;
SET enable_bitmapscan = on;
SET pg_ai_core.auto_fuse = off;
DO $$
BEGIN
  -- transaction-local set must have reverted by now (new transaction)
  IF current_setting('hnsw.iterative_scan') <> 'off' THEN
    RAISE EXCEPTION 'iterative_scan leaked across transactions: %', current_setting('hnsw.iterative_scan');
  END IF;
  RAISE NOTICE 'auto_fuse no-leak OK';
END $$;

-- 9) V2 runtime: tools + workflows (deterministic, no Ollama) + audit table
DO $$
DECLARE r text; n int;
BEGIN
  -- tools backed by built-in text functions
  PERFORM ai.register_tool('up',  'uppercase', 'upper(text)'::regprocedure);
  PERFORM ai.register_tool('rev', 'reverse',   'reverse(text)'::regprocedure);

  IF ai.run_tool('up', 'hi') <> 'HI' THEN
    RAISE EXCEPTION 'run_tool up failed: %', ai.run_tool('up','hi');
  END IF;

  -- workflow: uppercase then reverse  ('abc' -> 'ABC' -> 'CBA')
  PERFORM ai.register_workflow('w', '[{"kind":"tool","tool":"up"},{"kind":"tool","tool":"rev"}]'::jsonb);
  SELECT output INTO r FROM ai.run_workflow('w', 'abc') ORDER BY step DESC LIMIT 1;
  IF r <> 'CBA' THEN
    RAISE EXCEPTION 'run_workflow produced %, expected CBA', r;
  END IF;

  -- audit table exists and the opt-in GUC is readable
  SELECT count(*) INTO n FROM ai.audit;
  PERFORM set_config('pg_ai.audit', 'on', true);
  IF current_setting('pg_ai.audit', true) <> 'on' THEN
    RAISE EXCEPTION 'pg_ai.audit GUC not settable';
  END IF;

  RAISE NOTICE 'V2 runtime OK (tools, workflow=%, audit rows=%)', r, n;
END $$;

-- 10) async task queue plumbing (worker processing needs the runtime/Ollama)
DO $$
DECLARE tid bigint; st text;
BEGIN
  PERFORM ai.create_agent('qtest', 'queue test agent');
  tid := ai.submit_task('qtest', 'ping');
  IF tid IS NULL OR tid < 1 THEN
    RAISE EXCEPTION 'submit_task did not return an id';
  END IF;
  st := ai.task_status(tid);
  IF st NOT IN ('pending','running','done','error') THEN
    RAISE EXCEPTION 'unexpected task status: %', st;
  END IF;
  RAISE NOTICE 'async queue OK (task=%, status=%)', tid, st;

  -- async tool/workflow submission (plumbing; dispatched by kind)
  PERFORM ai.register_tool('up2', 'uppercase', 'upper(text)'::regprocedure);
  IF (SELECT kind FROM ai.tasks WHERE id = ai.submit_tool('up2', 'x')) <> 'tool' THEN
    RAISE EXCEPTION 'submit_tool did not set kind=tool';
  END IF;
  RAISE NOTICE 'async tool/workflow submission OK';
END $$;

\echo '=== ALL SMOKE TESTS PASSED ==='
