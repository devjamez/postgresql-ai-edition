-- PostgreSQL AI Edition — filtered ANN via PARTIAL indexes (recipe)
-- For LOW-CARDINALITY filters (a handful of known values), a partial HNSW index
-- per value constrains the ANN graph walk to matching rows. The search itself is
-- filtered (not post-filtered), so you get the correct top-k WITHOUT over-fetch
-- and without any pgvector fork. See docs-ai/RFC-0002-filtered-hnsw.md.
-- Run: docker compose exec -T db psql -U postgres -d pgai < examples/partial_index.sql

DROP TABLE IF EXISTS docs;
CREATE TABLE docs (id int, tier text, emb vector(768));

-- 5000 rows; ~1% are tier='premium'
INSERT INTO docs
SELECT g,
       CASE WHEN g % 100 = 0 THEN 'premium' ELSE 'free' END,
       ('[' || (SELECT string_agg(random()::text, ',') FROM generate_series(1,768)) || ']')::vector
FROM generate_series(1, 5000) g;

-- A PARTIAL HNSW index that only indexes the selective subset:
CREATE INDEX docs_premium_idx ON docs USING hnsw (emb vector_cosine_ops) WHERE tier = 'premium';

CREATE TEMP TABLE q AS
SELECT ('[' || (SELECT string_agg(random()::text, ',') FROM generate_series(1,768)) || ']')::vector AS v;

-- The planner uses the partial index for the matching filter; the walk only ever
-- visits 'premium' rows, so even with iterative scan OFF we get the full top-k.
SET hnsw.iterative_scan = off;

EXPLAIN
SELECT id FROM docs WHERE tier = 'premium'
ORDER BY emb <=> (SELECT v FROM q) LIMIT 10;

SELECT count(*) AS rows_returned
FROM (SELECT 1 FROM docs WHERE tier = 'premium'
      ORDER BY emb <=> (SELECT v FROM q) LIMIT 10) s;   -- expect 10

-- When to use which:
--   * partial index   -> few known filter values (tier, status, tenant_id, language)
--   * ai.filter_ann / pg_ai_core.auto_fuse (over-fetch) -> arbitrary/ad-hoc filters
