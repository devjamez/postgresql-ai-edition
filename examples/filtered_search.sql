-- PostgreSQL AI Edition — filtered ANN search (V2 M1)
-- Relational filter + vector ordering + top-k, with adaptive over-fetch.
-- Run after the stack is up and models are pulled:
--   docker compose exec -T db psql -U postgres -d pgai < examples/filtered_search.sql

CREATE TABLE IF NOT EXISTS articulos (
    id        serial PRIMARY KEY,
    categoria text,
    titulo    text,
    embedding vector(768)
);

INSERT INTO articulos (categoria, titulo) VALUES
    ('hardware', 'GPU para entrenamiento de redes neuronales profundas'),
    ('hardware', 'Notebook liviana para ofimática'),
    ('software', 'Framework de deep learning en Python'),
    ('software', 'Editor de texto para programar'),
    ('hardware', 'Servidor con muchas GPUs para IA'),
    ('software', 'Librería de visión por computadora');

UPDATE articulos SET embedding = ai.embed(titulo) WHERE embedding IS NULL;
CREATE INDEX IF NOT EXISTS articulos_emb_idx ON articulos USING hnsw (embedding vector_cosine_ops);

-- Semantic search WITHOUT a filter (everything ranked by similarity):
SELECT content, round(distance::numeric, 3) AS dist
FROM ai.filtered_search('entrenar modelos de inteligencia artificial',
                        'articulos', 'titulo', 'embedding', '{}'::jsonb, 3);

-- Same query, but FUSED with a relational filter (only category = 'hardware').
-- Filters are a safe jsonb of equality conditions (no SQL injection).
-- Adaptive over-fetch keeps pulling ANN candidates until 3 'hardware' rows pass:
SELECT content, round(distance::numeric, 3) AS dist
FROM ai.filtered_search('entrenar modelos de inteligencia artificial',
                        'articulos', 'titulo', 'embedding',
                        '{"categoria": "hardware"}'::jsonb, 3);

-- If you already have the query embedding, skip the model call with ai.filter_ann:
-- SELECT * FROM ai.filter_ann(ai.embed('...'), 'articulos','titulo','embedding','{"categoria":"software"}'::jsonb, 5);
-- For advanced predicates (ranges, LIKE), ai.filter_ann_raw(...) takes raw SQL (trusted input only).
