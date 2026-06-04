-- pg_ai 0.3.0 -> 0.4.0
-- RAG quality: document chunking + MMR reranking. Provider: also retry on 5xx.
\echo Use "ALTER EXTENSION pg_ai UPDATE TO '0.4.0'" to load this file. \quit

-- ---------------------------------------------------------------------------
-- Document chunking: split long text into overlapping windows for embedding.
-- ---------------------------------------------------------------------------
CREATE FUNCTION ai.chunk(doc text, max_chars int DEFAULT 1000, overlap int DEFAULT 100)
RETURNS SETOF text
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    n    int := length(doc);
    pos  int := 1;
    step int;
BEGIN
    IF doc IS NULL OR n = 0 THEN
        RETURN;
    END IF;
    IF max_chars < 1 THEN max_chars := 1000; END IF;
    IF overlap < 0 OR overlap >= max_chars THEN overlap := 0; END IF;
    step := max_chars - overlap;
    WHILE pos <= n LOOP
        RETURN NEXT substr(doc, pos, max_chars);
        pos := pos + step;
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- MMR reranking: fetch top fetch_n by ANN, then greedily pick k balancing
-- relevance to the query against diversity. lambda_weight in [0,1]:
-- 1.0 = pure relevance, 0.0 = pure diversity. (No model call.)
-- ---------------------------------------------------------------------------
CREATE FUNCTION ai.search_mmr(
    query_embedding  vector,
    source_table     regclass,
    content_column   text,
    embedding_column text,
    k                int   DEFAULT 5,
    fetch_n          int   DEFAULT 20,
    lambda_weight    float DEFAULT 0.5
) RETURNS TABLE (content text, score double precision)
LANGUAGE plpython3u AS $$
import math
sql = "SELECT {c}::text AS content, {e}::text AS emb FROM {t} ORDER BY {e} <=> $1 LIMIT {n}".format(
    c=plpy.quote_ident(content_column), e=plpy.quote_ident(embedding_column),
    t=source_table, n=int(fetch_n))
rows = plpy.execute(plpy.prepare(sql, ["vector"]), [query_embedding])

def parse(v):
    return [float(x) for x in v.strip('[]').split(',')] if v else []
def cos(a, b):
    s = sum(x*y for x, y in zip(a, b))
    na = math.sqrt(sum(x*x for x in a)); nb = math.sqrt(sum(y*y for y in b))
    return s/(na*nb) if na and nb else 0.0

q = parse(query_embedding)
cands = [{'content': r['content'], 'emb': parse(r['emb'])} for r in rows]
for c in cands:
    c['rel'] = cos(q, c['emb'])

selected, result = [], []
kk = int(k)
while cands and len(selected) < kk:
    best_i, best = None, None
    for i, c in enumerate(cands):
        div = max((cos(c['emb'], s['emb']) for s in selected), default=0.0)
        mmr = lambda_weight * c['rel'] - (1.0 - lambda_weight) * div
        if best is None or mmr > best:
            best, best_i = mmr, i
    chosen = cands.pop(best_i)
    selected.append(chosen)
    result.append({'content': chosen['content'], 'score': best})
return result
$$;

-- ---------------------------------------------------------------------------
-- Provider robustness: retry once on transient 5xx as well as network errors.
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
        if e.code >= 500 and attempt == 0:
            last = e; time.sleep(0.5); continue
        plpy.error('Ollama embeddings %d: %s' % (e.code, e.read().decode()))
    except urllib.error.URLError as e:
        last = e; time.sleep(0.5)
plpy.error('Ollama unreachable at %s: %s' % (base, getattr(last, 'reason', last)))
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
        if e.code >= 500 and attempt == 0:
            last = e; time.sleep(0.5); continue
        plpy.error('Ollama generate %d: %s' % (e.code, e.read().decode()))
    except urllib.error.URLError as e:
        last = e; time.sleep(0.5)
plpy.error('Ollama unreachable at %s: %s' % (base, getattr(last, 'reason', last)))
$$;
