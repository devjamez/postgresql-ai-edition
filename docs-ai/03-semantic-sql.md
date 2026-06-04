# FASE 3 — Semantic SQL

The original vision wanted SQL like `WHERE SEMANTIC_MATCH(description, '…')` and `SELECT AI_ASK('…')`. We deliver the same *capability* through functions/operators on stock PostgreSQL — no grammar changes.

## What you can write today

```sql
-- "semantic WHERE": rows whose embedding is close to a query's meaning
SELECT * FROM products
WHERE ai.semantic_match(embedding, 'notebook para desarrollo de IA', 0.75);

-- efficient ranked form (embed the query once)
WITH q AS (SELECT ai.embed('notebook para IA') AS v)
SELECT nombre FROM products ORDER BY embedding <=> (SELECT v FROM q) LIMIT 5;

-- ask a question grounded in your data
SELECT ai.rag('¿qué cliente tiene mayor riesgo de abandono?', 'clientes', 'perfil', 'embedding');

-- summarize
SELECT ai.complete('Resumí en una frase: ' || contenido) FROM articulos WHERE id = 1;

-- filtered semantic search (relational filter + vector order)
SELECT * FROM ai.filtered_search('GPU para IA', 'productos', 'nombre', 'embedding',
                                 '{"categoria":"hardware"}'::jsonb, 5);
```

## Vision → reality

| Vision | Shipped |
|---|---|
| `SEMANTIC_MATCH(col, text)` | `ai.semantic_match(col, text, threshold)` + the `<=>` operator (pgvector) |
| `AI_ASK('…')` | `ai.rag(...)` (grounded) / `ai.complete(...)` (free) |
| `AI_SUMMARIZE(text)` | `ai.complete('summarize…')` |

## Why functions, not new syntax

- **Compatibility:** new keywords mean patching `gram.y` and the parser (`pgsrc/src/backend/parser/`), which forks PostgreSQL and breaks every release upgrade. Functions run on stock PG (see [FASE 1](01-postgresql-anatomy.md) §1, ADR-0001).
- **Composability:** functions/operators compose with normal SQL (joins, CTEs, indexes, RLS) for free.
- **Transparency option:** for the one pattern where syntax *would* help (`WHERE … ORDER BY emb <=> $1 LIMIT k`), `pg_ai_core.auto_fuse` makes plain SQL auto-optimize via the planner/executor hooks — the benefit of "native" behavior without the fork (see [RFC-0001](RFC-0001-v2-plan-fusion.md)).

**Risk/compat:** none to standard SQL — everything is additive `ai.*` functions in a dedicated schema.
