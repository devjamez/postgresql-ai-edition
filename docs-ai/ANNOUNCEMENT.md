# Announcement drafts

Ready-to-post copy for launching PostgreSQL AI Edition (`pg_ai`). Publishing is manual (your accounts). Replace the repo URL if it changes.

Repo: https://github.com/devjamez/postgresql-ai-edition

---

## r/PostgreSQL (Reddit)

**Title:** pg_ai — embeddings, semantic search, RAG and agents inside PostgreSQL, with local inference (no API key)

**Body:**

I built an open-source PostgreSQL extension that brings AI primitives into the database itself — no external service, no API key required (inference runs locally via Ollama).

What it does, in plain SQL:

```sql
-- semantic search
WITH q AS (SELECT ai.embed('notebook para IA') v)
SELECT nombre FROM productos ORDER BY embedding <=> (SELECT v FROM q) LIMIT 3;

-- RAG grounded in your own tables
SELECT ai.rag('which product is best for training AI models?',
              'productos', 'descripcion', 'embedding');

-- agents with memory
SELECT ai.create_agent('advisor', 'You are a tech buying advisor.');
SELECT ai.call_agent('advisor', 'I need a laptop for programming');
```

- Installs as a normal extension: `CREATE EXTENSION pg_ai CASCADE;` (built on pgvector + PL/Python).
- Local inference via Ollama (nomic-embed-text + llama3.2) — zero cost, zero keys. Optional Anthropic provider for generation.
- Ships with `pg_ai_core`, a native C extension (planner hook + shared-memory telemetry + a Custom Scan provider) — the start of real engine-level relational+vector plan fusion (RFC in the repo).
- PostgreSQL License, Docker one-liner, CI, tests.

Feedback welcome — especially on the plan-fusion direction (RFC-0001 in docs-ai/).

---

## Hacker News (Show HN)

**Title:** Show HN: pg_ai – AI inside PostgreSQL (embeddings, RAG, agents) with local inference

**Body:**

pg_ai is a PostgreSQL extension that puts embeddings, semantic search, RAG and agents-with-memory directly in the database, callable from SQL. Inference runs locally through Ollama, so there's no API key and no per-call cost; an optional Anthropic provider is included for generation.

It installs as a normal extension (`CREATE EXTENSION pg_ai CASCADE`, on top of pgvector + PL/Python). There's also `pg_ai_core`, a native C extension that hooks the planner, keeps AI-workload telemetry in shared memory, and registers a Custom Scan provider — the foundation for fusing relational filters with vector ANN search at the plan level (the pre-filter/post-filter problem). The design is written up as an RFC in the repo.

It's early and honest about scope: the thin SQL/Python layer is the usable product today; the C plan-fusion work is a documented pilot. Docker quickstart, tests and CI are in the repo.

Repo: https://github.com/devjamez/postgresql-ai-edition

Happy to discuss the planner-integration approach.

---

## One-liner (Discord / Slack / Twitter-X)

Open-sourced **pg_ai**: embeddings, semantic search, RAG and agents *inside* PostgreSQL, with local inference (no API key). Installs as an extension on top of pgvector. Plus a native C pilot that hooks the planner for relational+vector fusion. https://github.com/devjamez/postgresql-ai-edition

---

## Tips
- Lead with the 30-second value: paste the semantic-search SQL, then the repo link.
- Be upfront that the C fusion is a pilot — HN/Reddit reward honesty about scope.
- Respond fast to the first comments; early engagement drives reach.
