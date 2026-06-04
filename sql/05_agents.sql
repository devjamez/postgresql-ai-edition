-- PostgreSQL AI Edition — pg_ai (thin edition)
-- 05: minimal agent engine. registry + memory + call.

CREATE TABLE IF NOT EXISTS ai.agents (
    id            serial PRIMARY KEY,
    name          text UNIQUE NOT NULL,
    system_prompt text NOT NULL,
    model         text NOT NULL DEFAULT 'gpt-4o-mini',
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ai.agent_memory (
    id         bigserial PRIMARY KEY,
    agent_id   int NOT NULL REFERENCES ai.agents(id) ON DELETE CASCADE,
    role       text NOT NULL CHECK (role IN ('user','assistant')),
    content    text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS agent_memory_agent_idx ON ai.agent_memory(agent_id, id);

CREATE OR REPLACE FUNCTION ai.create_agent(name text, system_prompt text, model text DEFAULT 'gpt-4o-mini')
RETURNS int
LANGUAGE sql AS $$
    INSERT INTO ai.agents(name, system_prompt, model)
    VALUES (name, system_prompt, model)
    ON CONFLICT (name) DO UPDATE
        SET system_prompt = EXCLUDED.system_prompt, model = EXCLUDED.model
    RETURNING id;
$$;

CREATE OR REPLACE FUNCTION ai.call_agent(agent_name text, message text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    a     ai.agents;
    hist  text;
    reply text;
BEGIN
    SELECT * INTO a FROM ai.agents WHERE name = agent_name;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'agent % not found', agent_name;
    END IF;

    -- last 10 turns, chronological
    SELECT string_agg(role || ': ' || content, E'\n' ORDER BY id)
      INTO hist
      FROM (SELECT id, role, content FROM ai.agent_memory
             WHERE agent_id = a.id ORDER BY id DESC LIMIT 10) h;

    reply := ai.complete(
        COALESCE(E'Conversación previa:\n' || hist || E'\n\n', '') || 'Usuario: ' || message,
        a.system_prompt, a.model);

    INSERT INTO ai.agent_memory(agent_id, role, content)
    VALUES (a.id, 'user', message), (a.id, 'assistant', reply);

    RETURN reply;
END;
$$;
