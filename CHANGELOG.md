# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/); versioning is [SemVer](https://semver.org/).

## [0.9.0] — 2026-06-04

### Added — scheduling (on top of the task worker)
- **Delayed tasks:** `ai.tasks.run_at`; `ai.submit_task/submit_tool/submit_workflow(..., run_at timestamptz DEFAULT now())` — a task runs no earlier than `run_at`. The worker only claims due tasks.
- **Recurring schedules:** `ai.schedules` + `ai.schedule(name, kind, target, input, period interval, first_run)` / `ai.unschedule(name)`. The worker calls `ai.tick_schedules()` each wake, enqueueing a task per due schedule and advancing `next_run` by `period`.

### Upgrade
- `ALTER EXTENSION pg_ai UPDATE TO '0.9.0';`

## [0.8.0] — 2026-06-04

### Added
- **LLM reranker:** `ai.rerank(query, table, content_col, emb_col, k, fetch_n)` — retrieves `fetch_n` by ANN, then a single model call orders the `k` most relevant (listwise; falls back to ANN order if parsing fails). More precise than MMR for final ranking.
- **Async tools & workflows:** `ai.submit_tool(tool, arg)` and `ai.submit_workflow(workflow, input)` enqueue work; the background worker now dispatches by task `kind` (`agent` / `tool` / `workflow`). `ai.tasks` gained a `kind` column.

### Upgrade
- `ALTER EXTENSION pg_ai UPDATE TO '0.8.0';`

## [0.7.0] — 2026-06-04

### Added — async agent runtime
- **Task queue:** `ai.tasks` + `ai.submit_task(agent, input) -> bigint` + `ai.task_status(id)` + `ai.task_result(id)`.
- **Background worker** (`pg_ai_core`, native C): drains the queue, runs each task's agent asynchronously (one transaction per task; the agent call is isolated in a subtransaction so a failing task is marked `error` and never crashes the worker). Opt-in via `pg_ai_core.enable_worker=on` (+ `pg_ai_core.task_db`, `pg_ai_core.worker_naptime`). Enabled by default in the Docker stack.
- Verified end-to-end: submit → worker processes → `done` with the agent's answer (worker idle when the queue is empty).

### Upgrade
- `ALTER EXTENSION pg_ai UPDATE TO '0.7.0';` (and set `pg_ai_core.enable_worker=on` to run the worker).

## [0.6.0] — 2026-06-04

### Added — synchronous V2 runtime
- **Agent tools:** `ai.tools` registry + `ai.register_tool(name, description, handler regprocedure)` + `ai.run_tool(name, arg)` (executes a registered SQL `text->text` function) + `ai.call_agent_tools(agent, message, max_steps)` (ReAct loop: the model picks `TOOL <name> <arg>` or `ANSWER <text>`).
- **Workflows:** `ai.workflows` registry + `ai.register_workflow(name, steps jsonb)` + `ai.run_workflow(name, input)` — ordered `tool`/`complete`/`rag` steps, each output feeds the next; returns the step trace.
- **Audit log:** `ai.audit` table; opt-in via `SET pg_ai.audit = on`. `ai.complete` / `ai.complete_claude` log kind/model/prompt/response/latency (guarded — an audit failure never breaks the call).

### Upgrade
- `ALTER EXTENSION pg_ai UPDATE TO '0.6.0';`

## [0.5.1] — 2026-06-04

### Added — V2 M2 transparent fusion (opt-in)
- `pg_ai_core.auto_fuse` GUC (default off): when on, the `ExecutorStart` hook detects a filtered-ANN query (`WHERE … ORDER BY emb <=> $1 LIMIT k`) and transparently sets `hnsw.iterative_scan = strict_order` **transaction-locally** (auto-reverts at transaction end, no cross-query leak). Plain SQL then returns the full top-k where a bounded ANN scan would under-return — no special function needed. Pure runtime feature of `pg_ai_core` (no SQL/version change).

## [0.5.0] — 2026-06-04

### Added
- `ai.health() -> jsonb` — reports Ollama reachability, which models are present, and the active config. Revoked from `PUBLIC` (network function).

### Upgrade
- `ALTER EXTENSION pg_ai UPDATE TO '0.5.0';`

## [0.4.0] — 2026-06-04

### Added — RAG quality
- `ai.chunk(doc, max_chars, overlap) -> setof text` — split long documents into overlapping windows for embedding.
- `ai.search_mmr(query_embedding, table, content_col, emb_col, k, fetch_n, lambda_weight) -> setof` — MMR reranking: balances relevance to the query against diversity (no model call).

### Changed
- Provider calls now retry once on transient `5xx` responses (in addition to network errors).

### Upgrade
- `ALTER EXTENSION pg_ai UPDATE TO '0.4.0';`

## [0.3.0] — 2026-06-04

Hardening release.

### Security
- **Filters are now safe by default.** `ai.filter_ann` / `ai.filtered_search` take a `jsonb` of equality conditions, built with `format('%I = %L', ...)` (identifiers validated, values escaped) — no SQL injection. The raw-SQL-predicate path moved to `ai.filter_ann_raw` (advanced; **trusted input only**).
- **Deny-by-default RBAC.** `EXECUTE` is revoked from `PUBLIC` on the powerful functions (`ai.embed`, `ai.embed_batch`, `ai.complete`, `ai.complete_claude`, `ai.filter_ann_raw`); a DBA grants them to trusted roles deliberately.

### Added
- `ai.embed_batch(text[]) -> vector[]` — embed many texts in **one** HTTP call.
- `ai.embedding_dim() -> int` — dimension of the current embedding model.
- `ai.rag(..., max_context int DEFAULT 4000)` — bounds the context size sent to the model.

### Changed
- Provider calls honor `AI_TIMEOUT` (seconds) and retry once on network failure.

### Upgrade
- `ALTER EXTENSION pg_ai UPDATE TO '0.3.0';`

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
