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

## Why in-database

The differentiator is **locality**: your embeddings live next to the relational rows they describe, so semantic search composes with `JOIN`/`WHERE`/RLS/transactions — no dual-write, no consistency drift between a SQL DB and a vector DB. The trade-off is horizontal vector-scale (a dedicated vector DB shards further); for the vast majority of apps that already run Postgres, locality wins.
