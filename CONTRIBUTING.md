# Contributing

Thanks for your interest in PostgreSQL AI Edition. Contributions are welcome.

## Project layout

| Path | What |
|---|---|
| `pg_ai/` | SQL extension: schema, model registry, provider, semantic search, RAG, agents |
| `pg_ai_core/` | Native **C** extension: planner hook + shared-memory AI-workload telemetry (V2 pilot) |
| `sql/00_init.sql` | First-boot install of both extensions |
| `examples/demo.sql` | End-to-end demo |
| `test/smoke.sql` | Key-free structural tests (run in CI) |
| `docs-ai/` | ADRs, testing & publishing plans, architecture |

## Dev environment

```bash
docker compose up -d --build
docker compose exec -T ollama ollama pull nomic-embed-text
docker compose exec -T ollama ollama pull llama3.1:8b
```

Reset a clean database (keeps Ollama models):
```bash
docker compose rm -fs db && docker volume rm postgresqlaiedition_pgai_data && docker compose up -d db
```

## Running tests

```bash
# structural smoke tests (no API key / model needed)
docker compose exec -T db psql -U postgres -d pgai -v ON_ERROR_STOP=1 -f - < test/smoke.sql

# full demo (needs Ollama models pulled)
docker compose exec -T db psql -U postgres -d pgai -f - < examples/demo.sql
```

CI runs the smoke tests on every push and PR.

## Making changes

- Keep diffs minimal and focused.
- SQL changes go in `pg_ai/pg_ai--<version>.sql`; bump the version and add an upgrade
  script (`pg_ai--<old>--<new>.sql`) for released versions.
- C changes go in `pg_ai_core/`; the Docker image rebuilds and `make install`s it.
- Add or update `test/smoke.sql` assertions for new objects.
- Never commit secrets. API keys/model hosts come from the server environment only.

## Versioning

Semantic versioning. Current: `pg_ai` 0.1.0, `pg_ai_core` 0.1.0. See [CHANGELOG.md](CHANGELOG.md).

## Where to contribute (open problems)

The thin layer and the agent runtime are complete. The deep-engine work (V2-recall / M3) is designed but unbuilt — these are the high-impact places to jump in. Start by reading [FASE 1 — Anatomy of PostgreSQL](docs-ai/01-postgresql-anatomy.md), then the relevant RFC.

### 🟢 Good first issues (learn the codebase, low risk)
- **Native AI types (M3-C).** A self-contained native type (e.g. a typed wrapper over `vector`, or a `prompt` type with validation) via `CREATE TYPE` + C I/O functions. Low blast radius, fully testable, great for learning the extension build (PGXS) and the type system ([FASE 1](docs-ai/01-postgresql-anatomy.md) §3). *Note: pgvector's `vector` already covers embeddings, so scope this to something that adds real value.*
- **More `pgTAP` assertions / examples / recipes.** See `test/pgtap/` and `examples/`.
- **A Helm chart** wrapping `deploy/k8s/` (currently raw manifests, untested on a live cluster).

### 🔴 Good first *hard* problem: in-walk filtered ANN (M3-A)
The headline open problem, fully specified in **[RFC-0002](docs-ai/RFC-0002-filtered-hnsw.md)**.

- **Goal:** evaluate the relational predicate *inside* the HNSW graph walk (not via over-fetch), for better recall/cost on selective filters.
- **Entry points (cited in RFC-0002):** `pgvector-src/src/hnswscan.c` (`hnswgettuple`, `GetScanItems`/`ResumeScanItems`), the `amgettuple` limitation (the qual isn't passed down), and per-node heap fetch during traversal.
- **Why it's hard (read before starting):** the failure mode is *silently wrong search results*, not a crash. **Required:** a recall benchmark vs. brute-force exact top-k across selectivities {50%, 10%, 1%, 0.1%} — a PR without it can't be reviewed. Prefer **upstreaming to pgvector** over a private fork.
- **Then M3-B (cost model):** once in-walk filtering exists, give the `pg_ai_fusion` custom scan a real cost so the planner chooses it automatically. Depends on M3-A.

### Ground rules for engine work
- Default to the **supported seams** (extensions, hooks, index AM, background workers) — see [ADR-0001](docs-ai/ADR-0001-extension-vs-fork.md). Forking core or pgvector is a last resort and must be justified.
- Anything touching ANN results ships with a **recall test**. Anything touching the worker/planner ships with a smoke + pgTAP assertion.

## License

By contributing you agree your contributions are licensed under the
[PostgreSQL License](LICENSE).
