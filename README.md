# PostgreSQL AI Edition — `pg_ai`

Make PostgreSQL intelligent: embeddings, semantic search, RAG and agents — **inside the database**, with maximum PostgreSQL compatibility.

This repository is the **thin edition**: a pure extension (no fork of the PostgreSQL C core) that delivers the full AI experience by orchestrating model APIs (OpenAI / Anthropic) from inside Postgres via PL/Python and SQL. It runs on **standard PostgreSQL** — no patched server.

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

## Requirements

- **Docker Desktop** (the only thing you must install).
- An **OpenAI API key** (required — embeddings + completion). An Anthropic key is optional, for Claude-generated answers.

> No GPU and no servers are needed: inference runs on the providers' servers via API. Self-hosted local models (Llama) are a future option.

## Quickstart

```bash
# 1. configure your key
cp .env.example .env
#   edit .env -> OPENAI_API_KEY=sk-...

# 2. build & start (first run pulls images + compiles the container)
docker compose up -d --build

# 3. load the AI layer (only needed if you reset the volume; init scripts auto-run on first boot)
#    the sql/ files run automatically on first initialization.

# 4. run the demo
docker compose exec -T db psql -U postgres -d pgai < examples/demo.sql
```

Reset everything (re-run init scripts): `docker compose down -v && docker compose up -d --build`.

## SQL surface

| Function | Purpose |
|---|---|
| `ai.embed(text) -> vector` | Embedding (OpenAI `text-embedding-3-small`, 1536d) |
| `ai.complete(prompt, system, model) -> text` | Completion via OpenAI |
| `ai.complete_claude(prompt, system, model, max_tokens) -> text` | Completion via Anthropic |
| `ai.similarity(a, b) -> float` | Cosine similarity in [0,1] |
| `ai.semantic_match(emb, query, threshold) -> bool` | Convenience predicate (small tables only) |
| `ai.rag(question, table, content_col, emb_col, k, model) -> text` | Retrieval-augmented answer |
| `ai.create_agent(name, system_prompt, model) -> int` | Register an agent |
| `ai.call_agent(name, message) -> text` | Call an agent (with memory) |

Catalog: `ai.models`, `ai.agents`, `ai.agent_memory`.

## Security

- API keys live only in the **server environment** (`.env` → container env). Never in SQL, never in the repo. `.env` is gitignored.
- `ai.embed`/`ai.complete*` use the **untrusted** `plpython3u` language → only superusers can create them; grant `EXECUTE` deliberately.
- Treat any text sent to `ai.complete`/`ai.rag` as untrusted input (prompt-injection surface). See [docs-ai/TESTING.md](docs-ai/TESTING.md) and the roadmap.

## Docs

- [ADR-0001 — Extension vs. Fork](docs-ai/ADR-0001-extension-vs-fork.md)
- [Testing plan](docs-ai/TESTING.md)
- [Publishing plan](docs-ai/PUBLISHING.md)
- [Master architecture prompt](docs-ai/00-master-prompt.md)

## License

[PostgreSQL License](LICENSE). Open source, free to use and modify.
