-- pg_ai 0.2.0 -> 0.3.0
-- Hardening: safe (parameterized) filters, batch embeddings, configurable
-- timeout + retry, RAG context budget, embedding-dim helper, deny-by-default RBAC.
\echo Use "ALTER EXTENSION pg_ai UPDATE TO '0.3.0'" to load this file. \quit

-- ---------------------------------------------------------------------------
-- Provider robustness: AI_TIMEOUT (seconds) + one retry on network failure
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ai.embed(input text)
RETURNS vector
LANGUAGE plpython3u AS $$
import os, json, urllib.request, urllib.error, time
base    = os.environ.get('OLLAMA_URL', 'http://ollama:11434')
model   = os.environ.get('AI_EMBED_MODEL', 'nomic-embed-text')
timeout = float(os.environ.get('AI_TIMEOUT', '120'))
body = json.dumps({'model': model, 'prompt': input}).encode()
last = None
for attempt in range(2):
    req = urllib.request.Request(base + '/api/embeddings', data=body, method='POST')
    req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            resp = json.loads(r.read().decode())
        vec = resp.get('embedding')
        if not vec:
            plpy.error('Ollama returned no embedding (model pulled?): %s' % json.dumps(resp)[:200])
        return '[' + ','.join(repr(x) for x in vec) + ']'
    except urllib.error.HTTPError as e:
        plpy.error('Ollama embeddings %d: %s' % (e.code, e.read().decode()))
    except urllib.error.URLError as e:
        last = e; time.sleep(0.5)
plpy.error('Ollama unreachable at %s: %s' % (base, last.reason if last else 'unknown'))
$$;

CREATE OR REPLACE FUNCTION ai.complete(prompt text, system text DEFAULT NULL, model text DEFAULT NULL)
RETURNS text
LANGUAGE plpython3u AS $$
import os, json, urllib.request, urllib.error, time
base    = os.environ.get('OLLAMA_URL', 'http://ollama:11434')
mdl     = model or os.environ.get('AI_CHAT_MODEL', 'llama3.1:8b')
timeout = float(os.environ.get('AI_TIMEOUT', '300'))
payload = {'model': mdl, 'prompt': prompt, 'stream': False}
if system:
    payload['system'] = system
body = json.dumps(payload).encode()
last = None
for attempt in range(2):
    req = urllib.request.Request(base + '/api/generate', data=body, method='POST')
    req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode()).get('response', '')
    except urllib.error.HTTPError as e:
        plpy.error('Ollama generate %d: %s' % (e.code, e.read().decode()))
    except urllib.error.URLError as e:
        last = e; time.sleep(0.5)
plpy.error('Ollama unreachable at %s: %s' % (base, last.reason if last else 'unknown'))
$$;

-- ---------------------------------------------------------------------------
-- Batch embeddings: ONE HTTP call for many texts (returns embeddings in order)
-- ---------------------------------------------------------------------------
CREATE FUNCTION ai.embed_batch(inputs text[])
RETURNS vector[]
LANGUAGE plpython3u AS $$
import os, json, urllib.request, urllib.error, time
base    = os.environ.get('OLLAMA_URL', 'http://ollama:11434')
model   = os.environ.get('AI_EMBED_MODEL', 'nomic-embed-text')
timeout = float(os.environ.get('AI_TIMEOUT', '300'))
body = json.dumps({'model': model, 'input': list(inputs)}).encode()
last = None
for attempt in range(2):
    req = urllib.request.Request(base + '/api/embed', data=body, method='POST')
    req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            resp = json.loads(r.read().decode())
        embs = resp.get('embeddings')
        if not embs:
            plpy.error('Ollama returned no embeddings: %s' % json.dumps(resp)[:200])
        return ['[' + ','.join(repr(x) for x in v) + ']' for v in embs]
    except urllib.error.HTTPError as e:
        plpy.error('Ollama embed %d: %s' % (e.code, e.read().decode()))
    except urllib.error.URLError as e:
        last = e; time.sleep(0.5)
plpy.error('Ollama unreachable at %s: %s' % (base, last.reason if last else 'unknown'))
$$;

-- Dimension of the current embedding model
CREATE FUNCTION ai.embedding_dim()
RETURNS int
LANGUAGE sql AS $$ SELECT vector_dims(ai.embed('dimension probe')) $$;

-- ---------------------------------------------------------------------------
-- Safe filtered ANN: equality filters from jsonb, built with format %I/%L
-- (identifiers validated, values escaped) -> no SQL injection.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS ai.filter_ann(vector, regclass, text, text, text, int);
DROP FUNCTION IF EXISTS ai.filtered_search(text, regclass, text, text, text, int);

CREATE FUNCTION ai.filter_ann(
    query_embedding  vector,
    source_table     regclass,
    content_column   text,
    embedding_column text,
    filters          jsonb DEFAULT '{}'::jsonb,
    k                int   DEFAULT 5
) RETURNS TABLE (content text, distance double precision)
LANGUAGE plpgsql AS $$
DECLARE
    where_sql text := 'true';
    key       text;
    parts     text[] := '{}';
BEGIN
    IF filters IS NOT NULL AND filters <> '{}'::jsonb THEN
        FOR key IN SELECT jsonb_object_keys(filters) LOOP
            parts := array_append(parts, format('%I = %L', key, filters ->> key));
        END LOOP;
        where_sql := array_to_string(parts, ' AND ');
    END IF;

    BEGIN
        SET LOCAL hnsw.iterative_scan = strict_order;
    EXCEPTION WHEN undefined_object THEN
        NULL;
    END;

    RETURN QUERY EXECUTE format(
        'SELECT %I::text, (%I <=> $1)::double precision '
        'FROM %s WHERE %s ORDER BY %I <=> $1 LIMIT %s',
        content_column, embedding_column, source_table::text,
        where_sql, embedding_column, k
    ) USING query_embedding;
END;
$$;

CREATE FUNCTION ai.filtered_search(
    query            text,
    source_table     regclass,
    content_column   text,
    embedding_column text,
    filters          jsonb DEFAULT '{}'::jsonb,
    k                int   DEFAULT 5
) RETURNS TABLE (content text, distance double precision)
LANGUAGE sql AS $$
    SELECT * FROM ai.filter_ann(ai.embed(query), source_table,
                                content_column, embedding_column, filters, k);
$$;

-- Escape hatch: raw SQL predicate. POWERFUL — SQL injection surface.
-- Revoked from PUBLIC; grant only to trusted roles.
CREATE FUNCTION ai.filter_ann_raw(
    query_embedding  vector,
    source_table     regclass,
    content_column   text,
    embedding_column text,
    predicate        text DEFAULT 'true',
    k                int  DEFAULT 5
) RETURNS TABLE (content text, distance double precision)
LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        SET LOCAL hnsw.iterative_scan = strict_order;
    EXCEPTION WHEN undefined_object THEN
        NULL;
    END;
    RETURN QUERY EXECUTE format(
        'SELECT %I::text, (%I <=> $1)::double precision '
        'FROM %s WHERE (%s) ORDER BY %I <=> $1 LIMIT %s',
        content_column, embedding_column, source_table::text,
        predicate, embedding_column, k
    ) USING query_embedding;
END;
$$;

-- ---------------------------------------------------------------------------
-- RAG: add a context-size budget (chars) to bound the prompt
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS ai.rag(text, regclass, text, text, int, text);

CREATE FUNCTION ai.rag(
    question         text,
    source_table     regclass,
    content_column   text,
    embedding_column text,
    k                int  DEFAULT 5,
    model            text DEFAULT NULL,
    max_context      int  DEFAULT 4000
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

    ctx := left(COALESCE(ctx, '(sin resultados)'), max_context);

    RETURN ai.complete(
        E'Contexto:\n' || ctx ||
        E'\n\nPregunta: ' || question ||
        E'\n\nRespondé únicamente con base en el contexto. Si la respuesta no está, decilo.',
        'Sos un asistente que responde solo con el contexto provisto.',
        model
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- RBAC: deny-by-default on powerful (network / raw-SQL) functions.
-- A DBA grants EXECUTE to trusted roles explicitly.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION ai.embed(text)                                         FROM PUBLIC;
REVOKE ALL ON FUNCTION ai.embed_batch(text[])                                 FROM PUBLIC;
REVOKE ALL ON FUNCTION ai.complete(text, text, text)                          FROM PUBLIC;
REVOKE ALL ON FUNCTION ai.complete_claude(text, text, text, int)              FROM PUBLIC;
REVOKE ALL ON FUNCTION ai.filter_ann_raw(vector, regclass, text, text, text, int) FROM PUBLIC;
