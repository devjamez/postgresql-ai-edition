-- pg_ai 0.8.0 -> 0.9.0
-- Scheduling on top of the task worker: delayed (run_at) + recurring (ai.schedules).
\echo Use "ALTER EXTENSION pg_ai UPDATE TO '0.9.0'" to load this file. \quit

-- ---------------------------------------------------------------------------
-- Delayed tasks: a task runs no earlier than run_at.
-- ---------------------------------------------------------------------------
ALTER TABLE ai.tasks ADD COLUMN run_at timestamptz NOT NULL DEFAULT now();
CREATE INDEX tasks_due_idx ON ai.tasks (run_at) WHERE status = 'pending';

-- Re-create submit_* with an optional run_at.
DROP FUNCTION ai.submit_task(text, text);
DROP FUNCTION ai.submit_tool(text, text);
DROP FUNCTION ai.submit_workflow(text, text);

CREATE FUNCTION ai.submit_task(agent text, input text, run_at timestamptz DEFAULT now())
RETURNS bigint LANGUAGE sql AS $$
    INSERT INTO ai.tasks(kind, agent, input, run_at) VALUES ('agent', agent, input, run_at) RETURNING id;
$$;
CREATE FUNCTION ai.submit_tool(tool text, arg text, run_at timestamptz DEFAULT now())
RETURNS bigint LANGUAGE sql AS $$
    INSERT INTO ai.tasks(kind, agent, input, run_at) VALUES ('tool', tool, arg, run_at) RETURNING id;
$$;
CREATE FUNCTION ai.submit_workflow(workflow text, input text, run_at timestamptz DEFAULT now())
RETURNS bigint LANGUAGE sql AS $$
    INSERT INTO ai.tasks(kind, agent, input, run_at) VALUES ('workflow', workflow, input, run_at) RETURNING id;
$$;

-- ---------------------------------------------------------------------------
-- Recurring schedules: enqueue a task every `period`.
-- ---------------------------------------------------------------------------
CREATE TABLE ai.schedules (
    id         bigserial PRIMARY KEY,
    name       text UNIQUE NOT NULL,
    kind       text NOT NULL DEFAULT 'agent' CHECK (kind IN ('agent','tool','workflow')),
    target     text NOT NULL,
    input      text NOT NULL DEFAULT '',
    period     interval NOT NULL,
    next_run   timestamptz NOT NULL DEFAULT now(),
    enabled    boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);
SELECT pg_catalog.pg_extension_config_dump('ai.schedules', '');

CREATE FUNCTION ai.schedule(name text, kind text, target text, input text,
                            period interval, first_run timestamptz DEFAULT now())
RETURNS bigint LANGUAGE sql AS $$
    INSERT INTO ai.schedules(name, kind, target, input, period, next_run)
    VALUES (name, kind, target, input, period, first_run)
    ON CONFLICT (name) DO UPDATE
        SET kind = EXCLUDED.kind, target = EXCLUDED.target, input = EXCLUDED.input,
            period = EXCLUDED.period, next_run = EXCLUDED.next_run, enabled = true
    RETURNING id;
$$;

CREATE FUNCTION ai.unschedule(name text)
RETURNS void LANGUAGE sql AS $$ UPDATE ai.schedules SET enabled = false WHERE name = $1; $$;

-- Fire all due schedules: enqueue a task for each and advance next_run.
-- Called by the background worker each wake.
CREATE FUNCTION ai.tick_schedules()
RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    WITH due AS (
        UPDATE ai.schedules SET next_run = next_run + period
        WHERE enabled AND next_run <= now()
        RETURNING kind, target, input
    ), ins AS (
        INSERT INTO ai.tasks(kind, agent, input)
        SELECT kind, target, input FROM due
        RETURNING 1
    )
    SELECT count(*) INTO n FROM ins;
    RETURN n;
END;
$$;
