-- PostgreSQL AI Edition — pg_ai (thin edition)
-- 04: RAG engine. retrieve top-k by vector distance -> build context -> complete.

CREATE OR REPLACE FUNCTION ai.rag(
    question         text,
    source_table     regclass,
    content_column   text,
    embedding_column text,
    k                int  DEFAULT 5,
    model            text DEFAULT 'gpt-4o-mini'
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
