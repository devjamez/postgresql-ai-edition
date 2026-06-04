-- PostgreSQL AI Edition — filtered ANN benchmark (no model needed; random vectors)
-- Shows why adaptive over-fetch matters: with a selective filter, a bounded ANN
-- scan (iterative off) under-returns, while ai.filter_ann (iterative strict)
-- returns the full top-k.
-- Run: docker compose exec -T db psql -U postgres -d pgai < examples/benchmark.sql
\timing on

DROP TABLE IF EXISTS bench;
CREATE TABLE bench (id int, cat text, emb vector(768));

-- 50k rows; only 1% match the selective filter (cat = 'rare')
INSERT INTO bench
SELECT g,
       CASE WHEN g % 100 = 0 THEN 'rare' ELSE 'common' END,
       ('[' || (SELECT string_agg(random()::text, ',') FROM generate_series(1,768)) || ']')::vector
FROM generate_series(1, 50000) g;

CREATE INDEX ON bench USING hnsw (emb vector_cosine_ops);

-- fixed query vector so both methods are comparable
CREATE TEMP TABLE qv AS
SELECT ('[' || (SELECT string_agg(random()::text, ',') FROM generate_series(1,768)) || ']')::vector AS v;

-- Force the HNSW index so we compare ANN paths (on large data the planner
-- picks the index anyway; forcing it makes the effect deterministic here).
SET enable_seqscan = off;
SET enable_bitmapscan = off;

-- NAIVE: bounded ANN candidate set, then filter (iterative scan OFF).
-- Returns FEWER than 10 because few of the ef_search candidates are 'rare'.
SET hnsw.iterative_scan = off;
SELECT count(*) AS naive_off_rows
FROM (SELECT 1 FROM bench WHERE cat = 'rare'
      ORDER BY emb <=> (SELECT v FROM qv) LIMIT 10) s;

-- FUSED: iterative strict_order -> adaptive over-fetch (what ai.filter_ann does).
-- Returns the full 10 nearest 'rare' rows.
SET hnsw.iterative_scan = strict_order;
SELECT count(*) AS fused_rows
FROM (SELECT 1 FROM bench WHERE cat = 'rare'
      ORDER BY emb <=> (SELECT v FROM qv) LIMIT 10) s;

-- Typical result: naive_off_rows = 4, fused_rows = 10 (selective filter on a
-- bounded ANN scan under-returns; adaptive over-fetch fixes it).
