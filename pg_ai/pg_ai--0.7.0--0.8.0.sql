-- pg_ai 0.7.0 -> 0.8.0
-- LLM reranker + async tool/workflow tasks (dispatched by kind in the worker).
\echo Use "ALTER EXTENSION pg_ai UPDATE TO '0.8.0'" to load this file. \quit

-- ---------------------------------------------------------------------------
-- Async task kinds: the background worker dispatches by kind.
-- (the existing `agent` column holds the target name: agent/tool/workflow)
-- ---------------------------------------------------------------------------
ALTER TABLE ai.tasks
    ADD COLUMN kind text NOT NULL DEFAULT 'agent'
    CHECK (kind IN ('agent','tool','workflow'));

CREATE FUNCTION ai.submit_tool(tool text, arg text)
RETURNS bigint
LANGUAGE sql AS $$
    INSERT INTO ai.tasks(kind, agent, input) VALUES ('tool', tool, arg) RETURNING id;
$$;

CREATE FUNCTION ai.submit_workflow(workflow text, input text)
RETURNS bigint
LANGUAGE sql AS $$
    INSERT INTO ai.tasks(kind, agent, input) VALUES ('workflow', workflow, input) RETURNING id;
$$;

-- ---------------------------------------------------------------------------
-- LLM reranker (listwise, one model call): retrieve fetch_n by ANN, then let
-- the model order the k most relevant. Falls back to ANN order on parse failure.
-- ---------------------------------------------------------------------------
CREATE FUNCTION ai.rerank(
    query            text,
    source_table     regclass,
    content_column   text,
    embedding_column text,
    k                int DEFAULT 5,
    fetch_n          int DEFAULT 20
) RETURNS TABLE (content text, rank int)
LANGUAGE plpython3u AS $$
import re
qv = plpy.execute(plpy.prepare("SELECT ai.embed($1) AS v", ["text"]), [query])[0]['v']
sql = "SELECT {c}::text AS content FROM {t} ORDER BY {e} <=> $1 LIMIT {n}".format(
    c=plpy.quote_ident(content_column), e=plpy.quote_ident(embedding_column),
    t=source_table, n=int(fetch_n))
rows = plpy.execute(plpy.prepare(sql, ["vector"]), [qv])
cands = [r['content'] for r in rows]
if not cands:
    return []
listing = "\n".join("%d. %s" % (i + 1, (c or '')[:300]) for i, c in enumerate(cands))
prompt = ("Pregunta: %s\n\nPasajes:\n%s\n\nDevolvé los numeros de los %d pasajes mas "
          "relevantes para la pregunta, del mas al menos relevante, separados por coma. "
          "Solo numeros." % (query, listing, int(k)))
resp = plpy.execute(plpy.prepare("SELECT ai.complete($1) AS a", ["text"]), [prompt])[0]['a'] or ''
order = []
for tok in re.findall(r'\d+', resp):
    idx = int(tok) - 1
    if 0 <= idx < len(cands) and idx not in order:
        order.append(idx)
    if len(order) >= int(k):
        break
if not order:
    order = list(range(min(int(k), len(cands))))
return [{'content': cands[i], 'rank': r + 1} for r, i in enumerate(order)]
$$;

-- network function (calls models): deny-by-default like the other providers
REVOKE ALL ON FUNCTION ai.rerank(text, regclass, text, text, int, int) FROM PUBLIC;
