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

## License

By contributing you agree your contributions are licensed under the
[PostgreSQL License](LICENSE).
