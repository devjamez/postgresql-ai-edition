# PostgreSQL AI Edition — `pg_ai`

[![CI](https://github.com/devjamez/postgresql-ai-edition/actions/workflows/ci.yml/badge.svg)](https://github.com/devjamez/postgresql-ai-edition/actions/workflows/ci.yml)

Make PostgreSQL intelligent: embeddings, semantic search, RAG and agents — **inside the database**, with maximum PostgreSQL compatibility.

This repository is the **thin edition**: a pure extension (no fork of the PostgreSQL C core) that delivers the full AI experience by orchestrating models from inside Postgres via PL/Python and SQL — by default **locally via Ollama** (no API key), with an optional Anthropic provider. It runs on **standard PostgreSQL** — no patched server.

> Why thin first? Forking the PostgreSQL C core is a multi-year, team-scale effort and breaks upstream compatibility. The thin edition ships the value now and keeps 100% compatibility. Native C internals (a semantic-aware planner, native types) are a later, surgical step — see [docs-ai/ADR-0001](docs-ai/ADR-0001-extension-vs-fork.md).

## What you get

```sql
-- semantic search
WITH q AS (SELECT ai.embed('notebook para desarrollo de IA') AS v)
SELECT nombre FROM productos ORDER BY embedding <=> (SELECT v FROM q) LIMIT 3;

-- RAG, grounded in your own tables
SELECT ai.rag('¿Qué laptop me conviene para IA?', 'productos', 'descripcion', 'embedding');

-- agents with memory
SELECT ai.create_agent('asesor', 'Sos un asesor de compras. Respondé corto.');
SELECT ai.call_agent('asesor', 'busco una laptop para programar');
```

**→ See [docs-ai/DEMO.md](docs-ai/DEMO.md) for real output** (semantic search, RAG, agent memory, filtered fusion).

## Architecture

```mermaid
flowchart LR
  Q["SQL: ai.rag / ai.filtered_search"] --> EMB["ai.embed → Ollama"]
  EMB --> IDX[("pgvector index (HNSW)")]
  IDX --> RANK["rank + relational filter (top-k)"]
  RANK --> CTX["build context"]
  CTX --> GEN["ai.complete → Ollama (llama3.1:8b)"]
  GEN --> ANS["answer / rows"]
  subgraph core["pg_ai_core (native C)"]
    PH["planner_hook"]
    TEL["shared-memory telemetry"]
    CS["pg_ai_fusion custom scan"]
  end
  PH -.observes.-> Q
```

Everything runs **inside PostgreSQL**. The thin layer (`pg_ai`) orchestrates a local model via PL/Python; `pg_ai_core` integrates with the engine in C. No external service, no API key.

## Requirements

- **Docker Desktop** (the only thing you must install).
- **~8 GB of free RAM** — the generation model runs locally on your machine.

> No API key and no GPU required: inference runs locally via Ollama (`nomic-embed-text` + `llama3.1:8b`). An optional Anthropic key enables Claude-generated answers (`ai.complete_claude`). A smaller model (e.g. `llama3.2`) works if RAM is tight — set `AI_CHAT_MODEL` in `docker-compose.yml`.

## Quickstart

```bash
# 1. build & start (first run pulls images + compiles the container)
docker compose up -d --build

# 2. pull the local models, one time (~5 GB; embeddings + generation)
docker compose exec -T ollama ollama pull nomic-embed-text
docker compose exec -T ollama ollama pull llama3.1:8b

# 3. extensions auto-install on first boot (sql/00_init.sql runs
#    CREATE EXTENSION pg_ai CASCADE + pg_ai_core). To install manually elsewhere:
#    psql> CREATE EXTENSION pg_ai CASCADE;   -- pulls in vector + plpython3u
#    psql> CREATE EXTENSION pg_ai_core;       -- native C planner pilot

# 4. run the demo
docker compose exec -T db psql -U postgres -d pgai < examples/demo.sql
```

Reset only the database (keeps the downloaded models):
`docker compose rm -fs db && docker volume rm postgresqlaiedition_pgai_data && docker compose up -d db`

## SQL surface

| Function | Purpose |
|---|---|
| `ai.embed(text) -> vector` | Embedding (Ollama `nomic-embed-text`, 768d) |
| `ai.complete(prompt, system, model) -> text` | Completion via Ollama (`llama3.1:8b`) |
| `ai.complete_claude(prompt, system, model, max_tokens) -> text` | Completion via Anthropic (optional) |
| `ai.similarity(a, b) -> float` | Cosine similarity in [0,1] |
| `ai.semantic_match(emb, query, threshold) -> bool` | Convenience predicate (small tables only) |
| `ai.rag(question, table, content_col, emb_col, k, model) -> text` | Retrieval-augmented answer |
| `ai.filter_ann(emb, table, content_col, emb_col, filter_sql, k) -> setof` | Filtered ANN: relational filter + vector order + top-k (adaptive over-fetch) |
| `ai.filtered_search(query, table, content_col, emb_col, filter_sql, k) -> setof` | `ai.filter_ann` with the query embedded for you |
| `ai.create_agent(name, system_prompt, model) -> int` | Register an agent |
| `ai.call_agent(name, message) -> text` | Call an agent (with memory) |

Catalog: `ai.models`, `ai.agents`, `ai.agent_memory`.

## Security

- The default setup uses local Ollama and needs **no API key**. Any optional key (e.g. Anthropic) lives only in the **server environment** (`.env` → container env) — never in SQL, never in the repo. `.env` is gitignored.
- `ai.embed`/`ai.complete*` use the **untrusted** `plpython3u` language → only superusers can create them; grant `EXECUTE` deliberately.
- Treat any text sent to `ai.complete`/`ai.rag` as untrusted input (prompt-injection surface). See [docs-ai/TESTING.md](docs-ai/TESTING.md) and the roadmap.

## V2 pilot — native C engine integration (`pg_ai_core`)

Beyond the SQL/Python thin layer, `pg_ai_core/` is a **compiled C extension** that integrates with PostgreSQL internals — the first step toward "intelligence inside the engine":

- Installs a **`planner_hook`** that intercepts AI-semantic queries at plan time (the mechanism for future relational + vector plan fusion).
- Keeps **cluster-wide telemetry in shared memory**: how many statements are planned vs. how many are AI-semantic.
- Provides a **Custom Scan provider** (`pg_ai_fusion`) registered via `set_rel_pathlist_hook` — the executable foundation for relational + vector plan fusion (see [docs-ai/RFC-0001](docs-ai/RFC-0001-v2-plan-fusion.md)). Opt-in per session:

```sql
SELECT pg_ai_core_version();
SELECT * FROM pg_ai_core_stats();   -- planned | ai_intercepted
SELECT pg_ai_core_reset();

SET pg_ai_core.fuse = on;           -- route base-table scans through the fusion node
EXPLAIN SELECT * FROM docs WHERE category = 'x';   -- Custom Scan (pg_ai_fusion)
```

It is built during the Docker image build (`postgresql-server-dev-16` + PGXS) and loaded via `shared_preload_libraries=pg_ai_core`.

**Status — M1 done:** filtered ANN (relational filter + vector order + top-k with adaptive over-fetch) ships as `ai.filter_ann` / `ai.filtered_search` (see [`examples/filtered_search.sql`](examples/filtered_search.sql)), built on pgvector's `hnsw.iterative_scan` — no engine fork. The C `pg_ai_fusion` custom-scan node is the foundation for **M2**: *transparent* fusion (plain `WHERE … ORDER BY emb <=> $1 LIMIT k` auto-optimized) and filtering inside the ANN graph walk. See [docs-ai/RFC-0001](docs-ai/RFC-0001-v2-plan-fusion.md).

## Docs

- [ADR-0001 — Extension vs. Fork](docs-ai/ADR-0001-extension-vs-fork.md)
- [Testing plan](docs-ai/TESTING.md)
- [Publishing plan](docs-ai/PUBLISHING.md)
- [Master architecture prompt](docs-ai/00-master-prompt.md)

## License

[PostgreSQL License](LICENSE). Open source, free to use and modify.
