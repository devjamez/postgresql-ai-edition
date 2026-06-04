-- PostgreSQL AI Edition — pg_ai (thin edition)
-- 03: semantic search helpers

-- Cosine similarity in [0,1] (pgvector <=> is cosine distance)
CREATE OR REPLACE FUNCTION ai.similarity(a vector, b vector)
RETURNS float
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT 1 - (a <=> b);
$$;

-- Convenience predicate. NOTE: re-embeds the query per row -> demo/small tables only.
-- For real queries embed the query ONCE in a CTE and ORDER BY embedding <=> query_vec.
CREATE OR REPLACE FUNCTION ai.semantic_match(content_embedding vector, query text, threshold float DEFAULT 0.75)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT (1 - (content_embedding <=> ai.embed(query))) >= threshold;
$$;
