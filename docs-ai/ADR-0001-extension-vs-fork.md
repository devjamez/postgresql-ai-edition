# ADR-0001 — Extension vs. Fork of the PostgreSQL core

- Status: Accepted
- Date: 2026-06-04
- Context: solo developer, open-source goal, first usable result targeted in days/weeks.

## Decision

Build PostgreSQL AI Edition as a **phased hybrid**, starting with a **pure extension** (`pg_ai`) on top of standard PostgreSQL. Defer any modification of the C core to a later, surgical phase justified by ROI.

## Options considered

### A. Fork the C core (native types, semantic-aware parser/planner)
- **Pros:** deepest integration; a planner that natively fuses relational + vector plans; native `VECTOR`/`AGENT` types.
- **Cons:** multi-year, team-scale C effort; must be re-based against every PostgreSQL release; **breaks the stated "maximum compatibility" goal**; nothing runs for a long time.
- **Verdict:** impossible for a solo dev on a short horizon. Directly contradicts the compatibility objective.

### B. Extension + external runtime (chosen for V1)
- **Pros:** runs on unmodified PostgreSQL → 100% ecosystem compatibility; deliverable solo in weeks; leverages `pgvector` for indexing and `plpython3u` for API calls; the AI surface is plain functions/operators.
- **Cons:** cannot change SQL grammar (no new native syntax — functions only); inference is out-of-process (API latency); `plpython3u` is untrusted (superuser to install).
- **Verdict:** the right starting point. This is exactly how `pgvector`, `PostGIS`, `TimescaleDB` reach users — as extensions, not core merges.

### C. Phased hybrid (chosen overall)
- Ship B now. Open the door to C-level work **only where the extension provably cannot deliver** — most likely planner integration for relational+vector plan fusion — once there is a team and a working product to justify it.

## Consequences

- The AI surface is delivered as `ai.*` functions/operators, not new SQL keywords.
- Embeddings depend on an external provider (OpenAI/Voyage) — Anthropic has no embeddings endpoint.
- Upgrading to native C internals later is additive, not a rewrite: the SQL surface stays stable.
