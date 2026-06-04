# FASE 5 — AI Storage Layer

What gets stored, where, and how `pg_ai` compares to standalone vector databases.

## What we store, and how

| Data | Storage in `pg_ai` |
|---|---|
| Embeddings | `vector` columns in **user tables** (pgvector); ride normal heap + TOAST + MVCC + WAL |
| Documents / chunks | `text`/`jsonb` columns; `ai.chunk()` splits long docs |
| Agent memory | `ai.agent_memory` (normal table, FK to `ai.agents`) |
| Conversations | rows in `ai.agent_memory` (role/content/timestamp) |
| Knowledge / RAG corpus | user tables with a `text` + `vector` column (see `examples/ingestion.sql`) |
| Model registry | `ai.models` |

Everything is **first-class PostgreSQL storage** — transactional, backup-able (`pg_dump`, with registry/agent tables flagged `pg_extension_config_dump`), replicated, RLS-able. No separate datastore to keep in sync.

## Comparison

| | pg_ai (Postgres+pgvector) | Pinecone | Weaviate | Chroma | Qdrant |
|---|---|---|---|---|---|
| Relational + vector in one place | **yes** | no | partial | no | no |
| Transactions / joins / SQL | **full** | no | limited | no | limited |
| Self-host / no API key | **yes** | no (SaaS) | yes | yes | yes |
| ANN index | HNSW/IVFFlat | proprietary | HNSW | HNSW | HNSW |
| Filtered ANN | over-fetch + partial-index (RFC-0002) | yes | yes | yes | **yes (native)** |
| Ops surface | one DB you already run | new service | new service | new service | new service |
| Scale ceiling (vectors) | high (sharding harder) | very high | high | medium | very high |

## What we incorporate natively vs delegate

- **Incorporate:** the AI *surface* (embed/search/RAG/agents), orchestration, telemetry, the planner integration — all inside Postgres.
- **Delegate to pgvector:** the vector type + ANN index (reuse, don't reinvent — ADR-0001).
- **Delegate to model providers:** inference (Ollama local / Anthropic remote).

## Why in-database (the technical case)

The classic AI stack runs **two datastores** (relational PostgreSQL + a vector DB) plus orchestration glue in the application tier. Putting the AI layer *inside* Postgres removes the second system. The concrete technical wins:

1. **One source of truth, ACID.** The embedding is a `vector` column on the same row it describes, written in the **same transaction**. The classic stack must dual-write (relational + vector store) and keep them in sync — re-embedding jobs, consistency windows, extra failure surface. In-database, there is no drift and no sync job.
2. **Semantic search composes with SQL.**
   ```sql
   SELECT p.* FROM productos p
   JOIN stock s ON s.producto_id = p.id
   WHERE s.disponible AND p.categoria = 'hardware'
   ORDER BY p.embedding <=> ai.embed('notebook para IA')
   LIMIT 5;
   ```
   JOIN + relational filter + semantic ordering + transaction, in one query. The two-store pattern instead does: query vector DB → return IDs → query Postgres → filter in app (more latency, more glue, and the "filter + similarity" combination is awkward). `ai.filter_ann` + adaptive over-fetch return the correct top-k even under selective filters.
3. **RBAC / RLS / multi-tenant for free.** `ai.rag`/`ai.filtered_search` honor the underlying tables' **Row-Level Security** and `GRANT`s — per-tenant isolation with zero authorization logic duplicated in an external AI service.
4. **Engine-level awareness.** `pg_ai_core` hooks the planner and registers a custom scan, so the engine recognizes and (optionally, transparently) optimizes filtered-ANN queries — not a wrapper around the DB but integration within it.
5. **Agent runtime in the database.** Agents, memory, tools, workflows, and an async background worker (queue + scheduling) are transactional, covered by normal `pg_dump`/PITR and streaming replication. No separate stateful service to run and keep consistent.
6. **Operational simplicity.** Local inference (Ollama, no API key) keeps sensitive data on the host, and you operate one system you already know — one backup, one HA model, one monitoring story — instead of adding a datastore with its own ops.

### Honest trade-offs (when NOT to)
- **Extreme vector scale:** a dedicated vector DB shards further toward billions of vectors; Postgres+pgvector scales high but sharding is more manual.
- **Managed PostgreSQL:** RDS/Cloud SQL usually disallow `plpython3u` (untrusted) → the inference layer needs self-managed PG (pgvector alone is available, the AI surface is not).

**Bottom line:** the win isn't "the same thing, faster" — it's **eliminating the second system**: embeddings and relational data live together with ACID, JOINs, RLS and transactions, and the engine becomes AI-aware from the inside. For the vast majority of apps already on Postgres, that's less complexity and fewer ways to break, not more.
