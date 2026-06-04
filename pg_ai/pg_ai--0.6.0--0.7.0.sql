-- pg_ai 0.6.0 -> 0.7.0
-- Async agent runtime: a task queue drained by the pg_ai_core background worker.
\echo Use "ALTER EXTENSION pg_ai UPDATE TO '0.7.0'" to load this file. \quit

CREATE TABLE ai.tasks (
    id         bigserial PRIMARY KEY,
    agent      text NOT NULL,
    input      text NOT NULL DEFAULT '',
    status     text NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending','running','done','error')),
    output     text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
SELECT pg_catalog.pg_extension_config_dump('ai.tasks', '');
CREATE INDEX tasks_pending_idx ON ai.tasks (id) WHERE status = 'pending';

-- Enqueue an agent run; returns the task id. Processed asynchronously by the
-- pg_ai_core worker (enable with pg_ai_core.enable_worker=on).
CREATE FUNCTION ai.submit_task(agent text, input text)
RETURNS bigint
LANGUAGE sql AS $$
    INSERT INTO ai.tasks(agent, input) VALUES (agent, input) RETURNING id;
$$;

CREATE FUNCTION ai.task_status(task_id bigint)
RETURNS text
LANGUAGE sql AS $$ SELECT status FROM ai.tasks WHERE id = task_id; $$;

CREATE FUNCTION ai.task_result(task_id bigint)
RETURNS text
LANGUAGE sql AS $$ SELECT output FROM ai.tasks WHERE id = task_id; $$;
