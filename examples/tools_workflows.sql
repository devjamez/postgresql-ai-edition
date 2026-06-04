-- PostgreSQL AI Edition — agent tools, workflows, and audit (V2 runtime)
-- Run: docker compose exec -T db psql -U postgres -d pgai < examples/tools_workflows.sql

-- 1) Tools: register SQL functions as agent-callable tools (text -> text).
SELECT ai.register_tool('uppercase', 'Uppercases the input text',  'upper(text)'::regprocedure);
SELECT ai.register_tool('reverse',   'Reverses the input text',    'reverse(text)'::regprocedure);
SELECT ai.run_tool('uppercase', 'hello');           -- HELLO

-- An agent that can call tools (ReAct loop). The model decides TOOL vs ANSWER.
SELECT ai.create_agent('helper', 'Sos un asistente. Usá herramientas cuando ayuden.');
SELECT ai.call_agent_tools('helper', 'Pasá a mayúsculas: postgresql ai edition', 4);

-- 2) Workflows: chain steps, each output feeds the next.
SELECT ai.register_workflow('shout_backwards',
    '[{"kind":"tool","tool":"uppercase"},{"kind":"tool","tool":"reverse"}]'::jsonb);
SELECT * FROM ai.run_workflow('shout_backwards', 'abc');   -- ABC -> CBA

-- A mixed workflow (deterministic tool + LLM step):
SELECT ai.register_workflow('summarize_upper',
    '[{"kind":"complete","prompt":"Resumí en 5 palabras: {input}"},{"kind":"tool","tool":"uppercase"}]'::jsonb);
SELECT * FROM ai.run_workflow('summarize_upper',
    'PostgreSQL AI Edition agrega embeddings, RAG y agentes dentro de la base de datos.');

-- 3) Audit: opt-in log of completions.
SET pg_ai.audit = on;
SELECT ai.complete('Decí hola en una palabra.');
SELECT kind, model, left(prompt, 30) AS prompt, left(response, 30) AS response, round(latency_ms) AS ms
FROM ai.audit ORDER BY id DESC LIMIT 5;
SET pg_ai.audit = off;
