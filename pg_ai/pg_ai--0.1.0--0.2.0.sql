-- pg_ai 0.1.0 -> 0.2.0
-- Adds filtered ANN search: relational filter + vector ordering + top-k, with
-- adaptive over-fetch via pgvector's iterative index scan (no engine fork).
\echo Use "ALTER EXTENSION pg_ai UPDATE TO '0.2.0'" to load this file. \quit

-- Core: filtered ANN over a precomputed query embedding (no model call).
-- `filter_sql` is a raw boolean SQL predicate on the row — pass TRUSTED input only.
CREATE FUNCTION ai.filter_ann(
    query_embedding  vector,
    source_table     regclass,
    content_column   text,
    embedding_column text,
    filter_sql       text DEFAULT 'true',
    k                int  DEFAULT 5
) RETURNS TABLE (content text, distance double precision)
LANGUAGE plpgsql AS $$
BEGIN
    -- Adaptive over-fetch: let the ANN index keep producing candidates past
    -- ef_search so a selective relational filter still yields k ordered rows.
    -- (No-op if the hnsw GUCs aren't loaded; results stay correct via seq scan.)
    BEGIN
        SET LOCAL hnsw.iterative_scan = strict_order;
    EXCEPTION WHEN undefined_object THEN
        NULL;
    END;

    RETURN QUERY EXECUTE format(
        'SELECT %I::text, (%I <=> $1)::double precision '
        'FROM %s WHERE (%s) ORDER BY %I <=> $1 LIMIT %s',
        content_column, embedding_column, source_table::text,
        filter_sql, embedding_column, k
    ) USING query_embedding;
END;
$$;

-- Convenience: embed a natural-language query, then filtered ANN search.
CREATE FUNCTION ai.filtered_search(
    query            text,
    source_table     regclass,
    content_column   text,
    embedding_column text,
    filter_sql       text DEFAULT 'true',
    k                int  DEFAULT 5
) RETURNS TABLE (content text, distance double precision)
LANGUAGE sql AS $$
    SELECT * FROM ai.filter_ann(ai.embed(query), source_table,
                                content_column, embedding_column, filter_sql, k);
$$;
