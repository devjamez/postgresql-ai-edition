-- PostgreSQL AI Edition — async agent runtime (background worker)
-- Requires the worker: start the stack with pg_ai_core.enable_worker=on
-- (the bundled docker-compose already does). Run:
--   docker compose exec -T db psql -U postgres -d pgai < examples/async_tasks.sql

SELECT ai.create_agent('asesor', 'Sos un asesor de tecnología. Respondé corto.');

-- Enqueue work; returns immediately with a task id (does NOT block on the model).
SELECT ai.submit_task('asesor', 'Recomendame una laptop para programar') AS task_id;

-- Poll for the result (the worker processes it in the background):
--   SELECT ai.task_status(1);   -- pending | running | done | error
--   SELECT ai.task_result(1);   -- the agent's answer once done

-- See the whole queue:
SELECT id, agent, status, left(coalesce(output,''), 60) AS output, created_at
FROM ai.tasks ORDER BY id DESC LIMIT 10;
