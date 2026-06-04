# Testing plan

Testing needs a running database and a valid API key, because the provider layer makes real HTTP calls. Layers, cheapest first:

## 1. Smoke test (no key needed)
Verify the extension installs and objects exist.
```sql
SELECT extname FROM pg_extension WHERE extname IN ('vector','plpython3u');
SELECT count(*) FROM ai.models;            -- 3 seeded rows
\df ai.*                                    -- functions present
```

## 2. Provider tests (key needed)
```sql
SELECT vector_dims(ai.embed('hello'));     -- expect 1536
SELECT length(ai.complete('say OK')) > 0;  -- expect t
```

## 3. Functional tests (key needed) — `pgTAP`
Install `pgTAP` and assert behavior:
- `ai.embed` returns a 1536-dim vector; deterministic dims across calls.
- `ai.similarity(v, v) = 1` for identical vectors; symmetric.
- `ai.rag` over a fixture table retrieves the expected top-k row (assert the relevant product appears in context).
- `ai.call_agent` writes exactly two `ai.agent_memory` rows per call and reuses prior turns.

Mock the provider where possible: wrap `ai.complete`/`ai.embed` behind a `search_path`-shadowable stub returning canned values, so functional tests run **without** a key or network and stay deterministic.

## 4. Security tests
- Prompt injection: feed adversarial content ("ignore previous instructions...") through `ai.rag` context and assert the system prompt constrains the answer.
- Confirm non-superusers cannot create `plpython3u` functions and only have `EXECUTE` where granted.
- Confirm no key material is ever returned by any function or present in `pg_stat_statements`.

## 5. The demo as regression
`examples/demo.sql` is the end-to-end happy path. Run it on every change against a disposable container:
```bash
docker compose down -v && docker compose up -d --build
docker compose exec -T db psql -U postgres -d pgai < examples/demo.sql
```

## CI (later)
GitHub Actions: spin up the container, run smoke + mocked functional tests on every PR (no key in CI). Key-dependent integration tests run on demand / nightly with a repo secret.
