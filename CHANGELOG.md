# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/); versioning is [SemVer](https://semver.org/).

## [0.2.0] — 2026-06-04

### Added
- `ai.filter_ann(query_embedding, table, content_col, emb_col, filter_sql, k)` — **filtered ANN search**: relational filter + vector ordering + top-k, with **adaptive over-fetch** via pgvector's iterative index scan (`hnsw.iterative_scan = strict_order`), so a selective filter still returns `k` ordered rows instead of under-returning from a bounded candidate set.
- `ai.filtered_search(query text, ...)` — convenience wrapper that embeds the query then calls `ai.filter_ann`.
- Default generation model is now `llama3.1:8b`.
- Upgrade path: `ALTER EXTENSION pg_ai UPDATE TO '0.2.0'`.

## [0.1.0] — 2026-06-04

First public release.

### Added — `pg_ai` 0.1.0 (SQL extension)
- Installable extension: `CREATE EXTENSION pg_ai CASCADE` (pulls in `vector` + `plpython3u`).
- `ai.embed(text) -> vector` — embeddings via Ollama (`nomic-embed-text`, 768d).
- `ai.complete(prompt, system, model)` — text generation via Ollama (`llama3.1:8b`).
- `ai.complete_claude(...)` — optional generation via the Anthropic API.
- `ai.similarity()` / `ai.semantic_match()` — cosine similarity helpers.
- `ai.rag(question, table, content_col, emb_col, k, model)` — retrieval-augmented generation.
- `ai.create_agent()` / `ai.call_agent()` — agents with persistent memory.
- Catalog: `ai.models`, `ai.agents`, `ai.agent_memory` (dumpable via `pg_extension_config_dump`).

### Added — `pg_ai_core` 0.1.0 (native C extension, V2 pilot)
- `planner_hook` that intercepts AI-semantic queries at plan time.
- Cluster-wide AI-workload telemetry in shared memory (`planned` vs `ai_intercepted`).
- `pg_ai_core_stats()`, `pg_ai_core_reset()`, `pg_ai_core_version()`, GUC `pg_ai_core.notice`.

### Infrastructure
- Docker Compose stack: PostgreSQL 16 + pgvector + PL/Python + Ollama (local, no API key).
- PGXN distribution manifest (`META.json`), standalone build guide (`INSTALL.md`).
- Smoke tests (`test/smoke.sql`) + GitHub Actions CI.
- Docs: ADR-0001 (extension vs fork), TESTING, PUBLISHING, master architecture prompt.

[0.1.0]: https://github.com/devjamez/postgresql-ai-edition/releases/tag/v0.1.0
