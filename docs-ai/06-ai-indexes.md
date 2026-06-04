# FASE 6 — AI Indexes

The proposed "Semantic / Embedding / Hybrid / Knowledge / Agent-memory" indexes, mapped to concrete, working index strategies on PostgreSQL.

| Proposed index | Concrete realization | Status |
|---|---|---|
| Embedding index | pgvector **HNSW** (`vector_cosine_ops`) / **IVFFlat** | ✅ |
| Semantic index | same HNSW + the `<=>` ordering operator (`amcanorderbyop`) | ✅ |
| Hybrid index (relational + vector) | **over-fetch** (`ai.filter_ann` + `iterative_scan`) and **partial HNSW indexes** per filter value (`examples/partial_index.sql`); true in-walk filtering is RFC-0002 | 🟡 (two working strategies; deep version deferred) |
| Knowledge index | HNSW over a chunked corpus + `ai.rag` (`examples/ingestion.sql`) | ✅ (composition) |
| Agent-memory index | btree on `ai.agent_memory(agent_id, id)`; optional `vector` column for semantic recall | ✅ |

## Structure / complexity / performance

- **HNSW** — multi-layer proximity graph. Build O(N·log N·M); query ~O(log N) with `ef_search` candidates. Excellent recall/latency; higher build cost + memory.
- **IVFFlat** — inverted lists over k-means centroids. Cheaper build, needs `lists`/`probes` tuning; lower memory.
- **Partial HNSW** — `CREATE INDEX … WHERE filter` indexes only the matching subset → the ANN walk is inherently filtered (correct top-k with no over-fetch). Best for low-cardinality filters. Cost: one index per value.
- **Distance ops** — `<=>` cosine, `<->` L2, `<#>` inner product (`pgvector-src/sql/vector.sql`).

## Footprint / tuning knobs
- `hnsw.ef_search` (candidate list size), `hnsw.iterative_scan` (off/relaxed/strict — the over-fetch control `auto_fuse` toggles), `hnsw.max_scan_tuples`.
- Storage: a `vector(d)` is `4·d + 8` bytes (varlena, TOAST-able). HNSW adds graph edges per element.

## Guidance
- Default: one HNSW index per embedding column.
- Selective, known filters: add **partial** indexes (FASE 6 / RFC-0002).
- Ad-hoc filters: `ai.filter_ann` / `auto_fuse` (over-fetch).
