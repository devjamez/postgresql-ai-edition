-- pg_ai 0.5.0 -> 0.6.0
-- Synchronous V2 runtime: agent tools, workflows, and an opt-in audit log.
\echo Use "ALTER EXTENSION pg_ai UPDATE TO '0.6.0'" to load this file. \quit

-- ---------------------------------------------------------------------------
-- Audit log (opt-in via: SET pg_ai.audit = on)
-- ---------------------------------------------------------------------------
CREATE TABLE ai.audit (
    id         bigserial PRIMARY KEY,
    ts         timestamptz NOT NULL DEFAULT now(),
    kind       text NOT NULL,
    model      text,
    prompt     text,
    response   text,
    latency_ms numeric
);
SELECT pg_catalog.pg_extension_config_dump('ai.audit', '');

-- ---------------------------------------------------------------------------
-- Tools: register a SQL function (text -> text) as an agent-callable tool
-- ---------------------------------------------------------------------------
CREATE TABLE ai.tools (
    name        text PRIMARY KEY,
    description text NOT NULL,
    handler     regprocedure NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
SELECT pg_catalog.pg_extension_config_dump('ai.tools', '');

CREATE FUNCTION ai.register_tool(name text, description text, handler regprocedure)
RETURNS void
LANGUAGE sql AS $$
    INSERT INTO ai.tools(name, description, handler)
    VALUES (name, description, handler)
    ON CONFLICT (name) DO UPDATE
        SET description = EXCLUDED.description, handler = EXCLUDED.handler;
$$;

CREATE FUNCTION ai.run_tool(tool_name text, arg text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE h regprocedure; res text;
BEGIN
    SELECT handler INTO h FROM ai.tools WHERE name = tool_name;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'tool % not found', tool_name;
    END IF;
    EXECUTE format('SELECT %s($1::text)::text', h::regproc) INTO res USING arg;
    RETURN res;
END;
$$;

-- ReAct-style agent loop: the model picks "TOOL <name> <arg>" or "ANSWER <text>".
CREATE FUNCTION ai.call_agent_tools(agent_name text, message text, max_steps int DEFAULT 4)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    a         ai.agents;
    tools_txt text;
    convo     text;
    reply     text;
    rest      text;
    tname     text;
    targ      text;
    obs       text;
    i         int := 0;
BEGIN
    SELECT * INTO a FROM ai.agents WHERE name = agent_name;
    IF NOT FOUND THEN RAISE EXCEPTION 'agent % not found', agent_name; END IF;

    SELECT string_agg(format('- %s: %s', name, description), E'\n') INTO tools_txt FROM ai.tools;
    convo := 'Usuario: ' || message;

    WHILE i < max_steps LOOP
        i := i + 1;
        reply := trim(ai.complete(
            convo,
            a.system_prompt
              || E'\n\nHerramientas:\n' || COALESCE(tools_txt, '(ninguna)')
              || E'\n\nPara usar una herramienta respondé EXACTAMENTE: TOOL <nombre> <argumento>.'
              || E'\nPara responder al usuario respondé: ANSWER <texto>.',
            a.model));

        IF left(reply, 6) = 'ANSWER' THEN
            reply := trim(substr(reply, 7));
            EXIT;
        ELSIF left(reply, 4) = 'TOOL' THEN
            rest  := trim(substr(reply, 5));
            tname := split_part(rest, ' ', 1);
            targ  := trim(substr(rest, length(tname) + 1));
            BEGIN
                obs := ai.run_tool(tname, targ);
            EXCEPTION WHEN OTHERS THEN
                obs := 'error: ' || SQLERRM;
            END;
            convo := convo || E'\nAsistente: ' || reply || E'\nObservación: ' || obs;
        ELSE
            EXIT;  -- model didn't follow the protocol; return its reply as-is
        END IF;
    END LOOP;

    INSERT INTO ai.agent_memory(agent_id, role, content)
    VALUES (a.id, 'user', message), (a.id, 'assistant', reply);
    RETURN reply;
END;
$$;

-- ---------------------------------------------------------------------------
-- Workflows: an ordered jsonb list of steps, output of each feeds the next.
-- step kinds: {"kind":"tool","tool":"name"} |
--             {"kind":"complete","prompt":"... {input} ...","system":"..."} |
--             {"kind":"rag","prompt":"...{input}...","table":"t","content_col":"c","emb_col":"e"}
-- ---------------------------------------------------------------------------
CREATE TABLE ai.workflows (
    name       text PRIMARY KEY,
    steps      jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
SELECT pg_catalog.pg_extension_config_dump('ai.workflows', '');

CREATE FUNCTION ai.register_workflow(name text, steps jsonb)
RETURNS void
LANGUAGE sql AS $$
    INSERT INTO ai.workflows(name, steps) VALUES (name, steps)
    ON CONFLICT (name) DO UPDATE SET steps = EXCLUDED.steps;
$$;

CREATE FUNCTION ai.run_workflow(workflow_name text, input text)
RETURNS TABLE (step int, kind text, output text)
LANGUAGE plpgsql AS $$
DECLARE w jsonb; s jsonb; prev text := input; i int := 0; k text; out text;
BEGIN
    SELECT steps INTO w FROM ai.workflows WHERE name = workflow_name;
    IF NOT FOUND THEN RAISE EXCEPTION 'workflow % not found', workflow_name; END IF;

    FOR s IN SELECT * FROM jsonb_array_elements(w) LOOP
        i := i + 1;
        k := s->>'kind';
        IF k = 'tool' THEN
            out := ai.run_tool(s->>'tool', prev);
        ELSIF k = 'complete' THEN
            out := ai.complete(replace(s->>'prompt', '{input}', prev), s->>'system', NULL);
        ELSIF k = 'rag' THEN
            out := ai.rag(replace(s->>'prompt', '{input}', prev),
                          (s->>'table')::regclass, s->>'content_col', s->>'emb_col');
        ELSE
            out := prev;
        END IF;
        prev := out;
        step := i; kind := k; output := out;
        RETURN NEXT;
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- Wire audit into the completion providers (opt-in; never breaks the call).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ai.complete(prompt text, system text DEFAULT NULL, model text DEFAULT NULL)
RETURNS text
LANGUAGE plpython3u AS $$
import os, json, urllib.request, urllib.error, time
base = os.environ.get('OLLAMA_URL', 'http://ollama:11434')
mdl  = model or os.environ.get('AI_CHAT_MODEL', 'llama3.1:8b')
timeout = float(os.environ.get('AI_TIMEOUT', '300'))
payload = {'model': mdl, 'prompt': prompt, 'stream': False}
if system:
    payload['system'] = system
body = json.dumps(payload).encode()
last = None; result = None; start = time.time()
for attempt in range(2):
    req = urllib.request.Request(base + '/api/generate', data=body, method='POST')
    req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            result = json.loads(r.read().decode()).get('response', '')
        break
    except urllib.error.HTTPError as e:
        if e.code >= 500 and attempt == 0:
            last = e; time.sleep(0.5); continue
        plpy.error('Ollama generate %d: %s' % (e.code, e.read().decode()))
    except urllib.error.URLError as e:
        last = e; time.sleep(0.5)
if result is None:
    plpy.error('Ollama unreachable at %s: %s' % (base, getattr(last, 'reason', last)))
try:
    a = plpy.execute("SELECT current_setting('pg_ai.audit', true) AS a")[0]['a']
    if a and a.lower() in ('on', 'true', '1', 'yes'):
        ms = (time.time() - start) * 1000.0
        plan = plpy.prepare("INSERT INTO ai.audit(kind,model,prompt,response,latency_ms) VALUES ($1,$2,$3,$4,$5)",
                            ["text", "text", "text", "text", "numeric"])
        plpy.execute(plan, ['complete', mdl, prompt[:4000], result[:4000], ms])
except Exception:
    pass
return result
$$;

CREATE OR REPLACE FUNCTION ai.complete_claude(prompt text, system text DEFAULT NULL,
                                              model text DEFAULT 'claude-sonnet-4-6', max_tokens int DEFAULT 1024)
RETURNS text
LANGUAGE plpython3u AS $$
import os, json, urllib.request, urllib.error, time
key = os.environ.get('ANTHROPIC_API_KEY')
if not key:
    plpy.error('ANTHROPIC_API_KEY not set in the database server environment')
payload = {'model': model, 'max_tokens': max_tokens, 'messages': [{'role': 'user', 'content': prompt}]}
if system:
    payload['system'] = system
body = json.dumps(payload).encode()
start = time.time()
req = urllib.request.Request('https://api.anthropic.com/v1/messages', data=body, method='POST')
req.add_header('Content-Type', 'application/json')
req.add_header('x-api-key', key)
req.add_header('anthropic-version', '2023-06-01')
try:
    with urllib.request.urlopen(req, timeout=120) as r:
        resp = json.loads(r.read().decode())
except urllib.error.HTTPError as e:
    plpy.error('Anthropic %d: %s' % (e.code, e.read().decode()))
result = ''.join(b.get('text', '') for b in resp.get('content', []))
try:
    a = plpy.execute("SELECT current_setting('pg_ai.audit', true) AS a")[0]['a']
    if a and a.lower() in ('on', 'true', '1', 'yes'):
        ms = (time.time() - start) * 1000.0
        plan = plpy.prepare("INSERT INTO ai.audit(kind,model,prompt,response,latency_ms) VALUES ($1,$2,$3,$4,$5)",
                            ["text", "text", "text", "text", "numeric"])
        plpy.execute(plan, ['complete_claude', model, prompt[:4000], result[:4000], ms])
except Exception:
    pass
return result
$$;
