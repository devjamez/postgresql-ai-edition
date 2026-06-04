-- pg_ai 0.1.0 — PostgreSQL AI Edition (thin edition)
-- Requires: vector, plpython3u (declared in pg_ai.control)
\echo Use "CREATE EXTENSION pg_ai CASCADE" to load this file. \quit

-- ---------------------------------------------------------------------------
-- Schema + model registry
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS ai;

CREATE TABLE ai.models (
    id         serial PRIMARY KEY,
    name       text UNIQUE NOT NULL,
    provider   text NOT NULL CHECK (provider IN ('ollama','openai','anthropic')),
    kind       text NOT NULL CHECK (kind IN ('embedding','completion')),
    model_id   text NOT NULL,
    dimensions int,
    created_at timestamptz NOT NULL DEFAULT now()
);
SELECT pg_catalog.pg_extension_config_dump('ai.models', '');

INSERT INTO ai.models (name, provider, kind, model_id, dimensions) VALUES
    ('default-embedding',  'ollama',    'embedding',  'nomic-embed-text',  768),
    ('default-completion', 'ollama',    'completion', 'llama3.2',          NULL),
    ('claude',             'anthropic', 'completion', 'claude-sonnet-4-6', NULL);

-- ---------------------------------------------------------------------------
-- Provider layer (local inference via Ollama; keys/URLs from server env)
-- ---------------------------------------------------------------------------
CREATE FUNCTION ai.embed(input text)
RETURNS vector
LANGUAGE plpython3u AS $$
import os, json, urllib.request, urllib.error
base  = os.environ.get('OLLAMA_URL', 'http://ollama:11434')
model = os.environ.get('AI_EMBED_MODEL', 'nomic-embed-text')
body = json.dumps({'model': model, 'prompt': input}).encode()
req = urllib.request.Request(base + '/api/embeddings', data=body, method='POST')
req.add_header('Content-Type', 'application/json')
try:
    with urllib.request.urlopen(req, timeout=120) as r:
        resp = json.loads(r.read().decode())
except urllib.error.HTTPError as e:
    plpy.error('Ollama embeddings %d: %s' % (e.code, e.read().decode()))
except urllib.error.URLError as e:
    plpy.error('Ollama unreachable at %s: %s' % (base, e.reason))
vec = resp.get('embedding')
if not vec:
    plpy.error('Ollama returned no embedding (model pulled?): %s' % json.dumps(resp)[:200])
return '[' + ','.join(repr(x) for x in vec) + ']'
$$;

CREATE FUNCTION ai.complete(prompt text, system text DEFAULT NULL, model text DEFAULT NULL)
RETURNS text
LANGUAGE plpython3u AS $$
import os, json, urllib.request, urllib.error
base = os.environ.get('OLLAMA_URL', 'http://ollama:11434')
mdl  = model or os.environ.get('AI_CHAT_MODEL', 'llama3.2')
payload = {'model': mdl, 'prompt': prompt, 'stream': False}
if system:
    payload['system'] = system
body = json.dumps(payload).encode()
req = urllib.request.Request(base + '/api/generate', data=body, method='POST')
req.add_header('Content-Type', 'application/json')
try:
    with urllib.request.urlopen(req, timeout=300) as r:
        resp = json.loads(r.read().decode())
except urllib.error.HTTPError as e:
    plpy.error('Ollama generate %d: %s' % (e.code, e.read().decode()))
except urllib.error.URLError as e:
    plpy.error('Ollama unreachable at %s: %s' % (base, e.reason))
return resp.get('response', '')
$$;

CREATE FUNCTION ai.complete_claude(prompt text, system text DEFAULT NULL,
                                   model text DEFAULT 'claude-sonnet-4-6', max_tokens int DEFAULT 1024)
RETURNS text
LANGUAGE plpython3u AS $$
import os, json, urllib.request, urllib.error
key = os.environ.get('ANTHROPIC_API_KEY')
if not key:
    plpy.error('ANTHROPIC_API_KEY not set in the database server environment')
payload = {'model': model, 'max_tokens': max_tokens, 'messages': [{'role': 'user', 'content': prompt}]}
if system:
    payload['system'] = system
body = json.dumps(payload).encode()
req = urllib.request.Request('https://api.anthropic.com/v1/messages', data=body, method='POST')
req.add_header('Content-Type', 'application/json')
req.add_header('x-api-key', key)
req.add_header('anthropic-version', '2023-06-01')
try:
    with urllib.request.urlopen(req, timeout=120) as r:
        resp = json.loads(r.read().decode())
except urllib.error.HTTPError as e:
    plpy.error('Anthropic %d: %s' % (e.code, e.read().decode()))
return ''.join(b.get('text', '') for b in resp.get('content', []))
$$;

-- ---------------------------------------------------------------------------
-- Semantic search helpers
-- ---------------------------------------------------------------------------
CREATE FUNCTION ai.similarity(a vector, b vector)
RETURNS float
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT 1 - (a <=> b);
$$;

CREATE FUNCTION ai.semantic_match(content_embedding vector, query text, threshold float DEFAULT 0.75)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT (1 - (content_embedding <=> ai.embed(query))) >= threshold;
$$;

-- ---------------------------------------------------------------------------
-- RAG engine
-- ---------------------------------------------------------------------------
CREATE FUNCTION ai.rag(
    question         text,
    source_table     regclass,
    content_column   text,
    embedding_column text,
    k                int  DEFAULT 5,
    model            text DEFAULT NULL
) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    q   vector;
    ctx text;
BEGIN
    q := ai.embed(question);
    EXECUTE format(
        'SELECT string_agg(t.%I::text, E''\n---\n'') FROM '
        '(SELECT %I FROM %s ORDER BY %I <=> $1 LIMIT %s) t',
        content_column, content_column, source_table::text, embedding_column, k
    ) INTO ctx USING q;

    RETURN ai.complete(
        E'Contexto:\n' || COALESCE(ctx, '(sin resultados)') ||
        E'\n\nPregunta: ' || question ||
        E'\n\nRespondé únicamente con base en el contexto. Si la respuesta no está, decilo.',
        'Sos un asistente que responde solo con el contexto provisto.',
        model
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- Minimal agent engine
-- ---------------------------------------------------------------------------
CREATE TABLE ai.agents (
    id            serial PRIMARY KEY,
    name          text UNIQUE NOT NULL,
    system_prompt text NOT NULL,
    model         text NOT NULL DEFAULT 'llama3.2',
    created_at    timestamptz NOT NULL DEFAULT now()
);
SELECT pg_catalog.pg_extension_config_dump('ai.agents', '');

CREATE TABLE ai.agent_memory (
    id         bigserial PRIMARY KEY,
    agent_id   int NOT NULL REFERENCES ai.agents(id) ON DELETE CASCADE,
    role       text NOT NULL CHECK (role IN ('user','assistant')),
    content    text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
SELECT pg_catalog.pg_extension_config_dump('ai.agent_memory', '');
CREATE INDEX agent_memory_agent_idx ON ai.agent_memory(agent_id, id);

CREATE FUNCTION ai.create_agent(name text, system_prompt text, model text DEFAULT 'llama3.2')
RETURNS int
LANGUAGE sql AS $$
    INSERT INTO ai.agents(name, system_prompt, model)
    VALUES (name, system_prompt, model)
    ON CONFLICT (name) DO UPDATE
        SET system_prompt = EXCLUDED.system_prompt, model = EXCLUDED.model
    RETURNING id;
$$;

CREATE FUNCTION ai.call_agent(agent_name text, message text)
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
