-- pg_ai — pgTAP unit tests (structure + RBAC + deterministic behavior; no Ollama)
-- Needs the image built with WITH_PGTAP=1, then CREATE EXTENSION pgtap;
--   docker compose exec -T db psql -U postgres -d pgai -t -A -q -f - < test/pgtap/pg_ai_test.sql
\set ON_ERROR_STOP on
BEGIN;
SELECT no_plan();

-- extensions / schema
SELECT has_extension('pg_ai');
SELECT has_extension('pg_ai_core');
SELECT has_schema('ai');

-- SQL surface (one assertion per function, robust to any signature)
SELECT ok(EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname = 'ai' AND p.proname = fn),
          format('function ai.%s exists', fn))
FROM unnest(ARRAY[
    'embed','embed_batch','complete','complete_claude','similarity','semantic_match',
    'rag','filter_ann','filtered_search','filter_ann_raw','search_mmr','rerank','chunk',
    'create_agent','call_agent','register_tool','run_tool','call_agent_tools',
    'register_workflow','run_workflow','submit_task','submit_tool','submit_workflow',
    'task_status','task_result','schedule','unschedule','tick_schedules',
    'embedding_dim','health'
]) AS fn;

-- catalog tables
SELECT ok(EXISTS(SELECT 1 FROM information_schema.tables
                 WHERE table_schema = 'ai' AND table_name = t),
          format('table ai.%s exists', t))
FROM unnest(ARRAY['models','agents','agent_memory','tools','workflows','audit','tasks','schedules']) AS t;

-- RBAC: network / raw functions revoked from PUBLIC; helpers available
SELECT ok(NOT has_function_privilege('public', 'ai.embed(text)', 'execute'),
          'ai.embed revoked from PUBLIC');
SELECT ok(NOT has_function_privilege('public', 'ai.complete(text,text,text)', 'execute'),
          'ai.complete revoked from PUBLIC');
SELECT ok(NOT has_function_privilege('public', 'ai.filter_ann_raw(vector,regclass,text,text,text,int)', 'execute'),
          'ai.filter_ann_raw revoked from PUBLIC');
SELECT ok(has_function_privilege('public', 'ai.similarity(vector,vector)', 'execute'),
          'ai.similarity available to PUBLIC');

-- deterministic behavior (no model needed)
SELECT lives_ok($$ SELECT ai.register_tool('t_up', 'uc', 'upper(text)'::regprocedure) $$,
                'register_tool works');
SELECT is(ai.run_tool('t_up', 'hi'), 'HI', 'run_tool executes the handler');
SELECT is((SELECT count(*)::int FROM ai.chunk(repeat('x', 500), 200, 20)), 3,
          'chunk splits into overlapping windows');

SELECT * FROM finish();
ROLLBACK;
