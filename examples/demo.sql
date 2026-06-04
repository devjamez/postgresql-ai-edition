-- PostgreSQL AI Edition — demo
-- Run after the stack is up:
--   docker compose exec -T db psql -U postgres -d pgai -f - < examples/demo.sql
-- or from psql:  \i examples/demo.sql

CREATE TABLE IF NOT EXISTS productos (
    id          serial PRIMARY KEY,
    nombre      text,
    descripcion text,
    embedding   vector(1536)
);

INSERT INTO productos (nombre, descripcion) VALUES
    ('MacBook Pro M3',     'Notebook potente para desarrollo de software, machine learning y compilación pesada'),
    ('Logitech MX Master', 'Mouse ergonómico para oficina y productividad'),
    ('Dell XPS 15',        'Laptop para desarrolladores con buena GPU para entrenar modelos de IA'),
    ('Teclado mecánico',   'Teclado para escritura y gaming'),
    ('iPad Air',           'Tablet para consumo de contenido y notas');

-- Generate embeddings for rows that don't have one yet
UPDATE productos SET embedding = ai.embed(descripcion) WHERE embedding IS NULL;

-- 1) Semantic search (efficient pattern: embed the query ONCE)
WITH q AS (SELECT ai.embed('notebook para desarrollo de IA') AS v)
SELECT nombre,
       round(ai.similarity(embedding, (SELECT v FROM q))::numeric, 3) AS score
FROM productos
ORDER BY embedding <=> (SELECT v FROM q)
LIMIT 3;

-- 2) RAG: answer grounded in the table
SELECT ai.rag('¿Qué producto me conviene para entrenar modelos de IA?',
              'productos', 'descripcion', 'embedding', 3) AS respuesta;

-- 3) Agent with memory
SELECT ai.create_agent('asesor',
    'Sos un asesor de compras de tecnología. Respondé corto y directo, en español.');
SELECT ai.call_agent('asesor', 'Hola, busco una laptop para programar')        AS turno_1;
SELECT ai.call_agent('asesor', '¿Y para jugar también sirve?')                  AS turno_2;  -- recuerda contexto
