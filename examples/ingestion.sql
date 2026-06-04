-- PostgreSQL AI Edition — document ingestion pipeline
-- chunk -> batch-embed (one HTTP call) -> store -> search / MMR / RAG.
-- Run: docker compose exec -T db psql -U postgres -d pgai < examples/ingestion.sql

CREATE TABLE IF NOT EXISTS kb (
    id        serial PRIMARY KEY,
    chunk     text,
    embedding vector(768)
);

-- 1) chunk a long document into overlapping windows
WITH doc AS (
    SELECT repeat('PostgreSQL is a powerful, extensible relational database. ', 30)
        || 'pgvector adds vector similarity search to Postgres. '
        || 'pg_ai adds embeddings, semantic search, RAG and agents inside the database. '
        || repeat('Ollama runs models locally with no API key and no GPU required for small models. ', 15)
        AS body
)
INSERT INTO kb (chunk)
SELECT ai.chunk(body, 200, 40) FROM doc;

-- 2) batch-embed every new chunk in ONE HTTP call, mapped back by id
WITH todo AS (
    SELECT array_agg(id ORDER BY id) AS ids, array_agg(chunk ORDER BY id) AS texts
    FROM kb WHERE embedding IS NULL
),
emb AS (
    SELECT ids, ai.embed_batch(texts) AS embs FROM todo WHERE array_length(ids,1) > 0
)
UPDATE kb SET embedding = u.e
FROM emb, unnest(emb.ids, emb.embs) AS u(id, e)
WHERE kb.id = u.id;

SELECT count(*) AS chunks_ingested, count(embedding) AS embedded FROM kb;

-- 3) semantic search over the ingested chunks
WITH q AS (SELECT ai.embed('how does pg_ai run models?') AS v)
SELECT left(chunk, 60) AS snippet, round((1 - (embedding <=> (SELECT v FROM q)))::numeric, 3) AS sim
FROM kb ORDER BY embedding <=> (SELECT v FROM q) LIMIT 3;

-- 4) diversified retrieval with MMR reranking
SELECT left(content, 60) AS snippet, round(score::numeric, 3) AS mmr
FROM ai.search_mmr(ai.embed('how does pg_ai run models?'), 'kb', 'chunk', 'embedding', 3, 10, 0.5);

-- 5) RAG answer grounded in the ingested document
SELECT ai.rag('How does pg_ai run models and what does it add to Postgres?',
              'kb', 'chunk', 'embedding', 4);
