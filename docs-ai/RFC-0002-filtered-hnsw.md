# RFC-0002 — Filtered HNSW: pushing the relational filter into the ANN walk (M2-recall)

- Status: Draft / contributor-ready spec (NOT implemented)
- Date: 2026-06-04
- Depends on: [RFC-0001](RFC-0001-v2-plan-fusion.md). Researched against the real pgvector source at `pgvector-src/src/`.

## Why this is a separate, harder RFC

M1 + M2-transparent (shipped) make a filtered ANN query **correct** via **over-fetch**: keep pulling ANN candidates (pgvector `hnsw.iterative_scan`) and post-filter until the top-k that pass the relational predicate are found. For selective filters this can scan many candidates. **M2-recall** wants to instead evaluate the filter *during* the graph walk so the search itself avoids non-matching regions. This is materially harder, and this RFC documents exactly why and how — so a contributor can pick it up without rediscovering the obstacle.

## The architectural obstacle (from source)

pgvector's HNSW scan returns candidates in distance order and knows **only** the vector ordering:

- `hnswgettuple()` — `pgvector-src/src/hnswscan.c:189`. First call runs `GetScanItems()` (`:230`); subsequent calls, under `hnsw_iterative_scan != OFF`, run `ResumeScanItems()` (`:280`) to continue the walk (this is the over-fetch we use).
- The scan operates on `scan->orderByData` (the query vector) and emits `heaptid`s (`:247`, `:297`). It has **no access to the relational qual** on other columns (e.g. `cat = 'rare'`).
- In the executor, that relational predicate is a **qpqual applied above the index scan** (`pgsrc/src/backend/executor/nodeIndexscan.c`), after the AM returns each tuple — i.e. strictly post-filtering.

So "filter inside the walk" needs two things the AM API does not give you:

1. **The predicate, pushed into the index scan.** `amgettuple` (`pgsrc/src/include/access/amapi.h`) receives only `ScanKey`s for the indexed column(s); arbitrary relational quals on *other* columns are not passed down.
2. **Per-node heap access during traversal.** To test `cat = 'rare'` on a visited HNSW node you must fetch that node's heap tuple mid-walk and evaluate the expression — index AMs deliberately don't fetch the heap during traversal (the executor does, afterwards).

This is the open problem usually called **filtered / predicate-constrained ANN**. It is active research and engineering in the vector-DB space, not a tidy patch.

## Approaches (with honest cost)

1. **Accept over-fetch (shipped).** `hnsw.iterative_scan = strict_order` + post-filter. Correct top-k; cost grows as the filter gets more selective. This is M1/M2-transparent — already in `pg_ai`. For most workloads this is enough.
2. **Predicate pushdown into a pgvector fork.** Extend the scan to carry an `ExprState` for the filter and evaluate it against each visited node's heap tuple inside `HnswSearchLayer`/`ResumeScanItems`, counting only matches toward `ef`/`k`. Requires: a way to pass the qual into the scan (custom scan provider feeding the index scan, or an index AM extension), heap fetches during the walk (TID → buffer → `heap_fetch` → `ExecQual`), and careful interaction with `iterative_scan`'s discard list (`hnswscan.c:255-266`) and locking (`HNSW_SCAN_LOCK`, `:228`). **Maintenance burden:** a vendored pgvector fork tracked against upstream — contradicts ADR-0001's "reuse pgvector / max compatibility" stance unless upstreamed.
3. **Partitioned / partial indexes (IMPLEMENTED as a recipe).** For low-cardinality filters (e.g. `tier`), build a partial HNSW index per value (`CREATE INDEX ... WHERE tier = 'premium'`). Pure SQL, no fork; the planner picks the matching partial index and the ANN walk is **already constrained to matching rows** — correct top-k with *no over-fetch*, even with `iterative_scan = off`. Verified in [`examples/partial_index.sql`](../examples/partial_index.sql) (uses `docs_premium_idx`, returns the full 10). **Best near-term option for known, low-cardinality filters.**
4. **Upstream collaboration.** Filtered ANN is on the radar of the pgvector/pgvector-adjacent community; contributing there beats maintaining a private fork.

## Recommendation

- **Now:** keep over-fetch (M2-transparent) as the default; add a **recipe** for partial-index pushdown (approach 3) for low-cardinality filters — that is the highest value with zero fork risk.
- **Later (team / upstream):** approach 2/4 — true in-walk filtering. Treat as research; gate on rigorous **recall benchmarking** (compare against brute-force exact top-k across selectivities), because the failure mode is *silently wrong results*, which ordinary tests do not catch.

## Why this was not auto-implemented

A blind, unattended pgvector fork that filters during the HNSW walk would risk returning subtly wrong nearest-neighbour results that no smoke test can certify. That is a worse failure than a crash. This RFC is the responsible deliverable: the exact obstacle, the source lines, the viable approaches, and the test bar — ready for a focused, reviewed effort.

## Implementation pointers (for a contributor)

- pgvector scan: `pgvector-src/src/hnswscan.c` — `hnswbeginscan`, `hnswrescan` (`:165`), `hnswgettuple` (`:189`), `GetScanItems`/`ResumeScanItems`, opaque state `HnswScanOpaqueData` (`pgvector-src/src/hnsw.h`).
- Search core: `HnswSearchLayer` (`pgvector-src/src/hnswutils.c`), `hnsw_ef_search`/`hnsw_iterative_scan`/`hnsw_max_scan_tuples` GUCs (`hnsw.c:93-107`).
- Heap eval during walk: `heap_fetch` (`pgsrc/src/backend/access/heap/heapam.c`), `ExecQual`/`ExecInitQual` (`pgsrc/src/backend/executor/execExpr.c`).
- Test bar: recall vs brute-force exact (seq scan + sort) over selectivities {50%, 10%, 1%, 0.1%}; assert recall ≥ target at each, plus latency.
