# RFC-0001 — V2: Relational + Vector Plan Fusion

- Status: Draft
- Date: 2026-06-04
- Scope: native C engine integration (`pg_ai_core`) beyond the V1 pilot.
- Method: researched against the real PostgreSQL 16 (`REL_16_STABLE`) and pgvector source. Every API claim below carries a `file:line` citation; items that could not be verified in-source are marked `[ASSUMED]`.

## 1. Problem

A query that combines a **relational filter** with a **vector ANN ordering** is planned as two competing, mutually exclusive paths:

```sql
SELECT * FROM docs WHERE category = $1 ORDER BY embedding <=> $2 LIMIT k;
```

- **Path A (relational-driven):** index/seq scan on `category`, then sort by distance → correct but pays a full sort, no ANN speedup.
- **Path B (ANN-driven):** vector index ordered scan on `embedding`, then filter → fast ordering but **post-filtering**: it returns the global top-N by distance and *then* drops the ones failing `category = $1`, so it can return fewer than `k` rows (or miss the true filtered neighbours).

The planner picks one by cost; neither fuses the two. This is the well-known **pre-filter vs. post-filter** problem. pgvector's `amcanorderbyop` ordering path and the restriction-clause path are matched independently and never combined into one plan node.

## 2. Verified findings

### 2.1 Planner hook & plan tree
- `planner_hook` is invoked at `planner()` — `pgsrc/src/backend/optimizer/plan/planner.c:279-282`; declared `pgsrc/src/include/optimizer/planner.h:26-30`. It returns a full `PlannedStmt`.
- WARNING in-source: `standard_planner()` scribbles on its `Query` input — copy it if planning twice (`planner.c:269-270`).
- Path→Plan happens in `create_plan()` / `create_plan_recurse()` (`pgsrc/src/backend/optimizer/plan/createplan.c:336-412`); the chosen path is `get_cheapest_fractional_path` (`planner.c:419`).
- `create_upper_paths_hook` lets an extension add **paths** (pre-plan) at each upper stage (`planner.c:2018-2020`). This is the place to add a path before the plan is frozen, rather than rewriting a finished `PlannedStmt`.

### 2.2 Custom Scan / Custom Path API (the supported extension seam)
- Structs/callbacks: `pgsrc/src/include/nodes/extensible.h:92-158` — `CustomPathMethods` (mandatory `PlanCustomPath`), `CustomScanMethods` (mandatory `CreateCustomScanState`), `CustomExecMethods` (mandatory `BeginCustomScan`/`ExecCustomScan`/`EndCustomScan`/`ReScanCustomScan`).
- Nodes: `CustomPath` (`pgsrc/src/include/nodes/pathnodes.h:1865-1873`), `CustomScan` (`pgsrc/src/include/nodes/plannodes.h:738-755`), `CustomScanState` (`pgsrc/src/include/nodes/execnodes.h:1984-1993`).
- Registration: `RegisterCustomScanMethods()` (`pgsrc/src/backend/nodes/extensible.c:88-94`).
- Wiring: add a `CustomPath` via `add_path()` from `set_rel_pathlist_hook`; core turns it into a `CustomScan` in `create_customscan_plan()` (`pgsrc/src/backend/optimizer/plan/createplan.c:4251-4312`); executor entry `ExecInitCustomScan()` (`pgsrc/src/backend/executor/nodeCustom.c:29-114`).
- Note: there is **no in-tree example** of a custom scan provider; the contract lives in the header/source comments.

### 2.3 pgvector seam
- HNSW/IVFFlat register as index AMs with `amcanorderbyop = true` (`pgvector-src/src/hnsw.c:277`, `pgvector-src/src/ivfflat.c:194`).
- Distance ops `<->`,`<#>`,`<=>` are registered `FOR ORDER BY` (`pgvector-src/sql/vector.sql:174-186`).
- The ordered scan **requires** an ORDER BY key — `hnswgettuple` errors if `scan->orderByData == NULL` (`pgvector-src/src/hnswscan.c:214`); it has no filter-during-traversal API today.
- Planner matches ordering via `match_pathkeys_to_index()` (`pgsrc/src/backend/optimizer/path/indxpath.c:975-985`) independently of restriction-clause matching (`indxpath.c:2016-2022`).

### 2.4 Hooks & safety
- Best injection point: `set_rel_pathlist_hook` — declared `pgsrc/src/include/optimizer/paths.h:29-33`, called `pgsrc/src/backend/optimizer/path/allpaths.c:541-542` (after core paths, before gather).
- `add_path()` keeps the cheapest by fuzzy cost, `STD_FUZZ_FACTOR = 1.01` (`pgsrc/src/backend/optimizer/util/pathnode.c:52`): a custom path within ~1% of the best may be discarded — **cost calibration is mandatory** or the path is never chosen.
- Parallel: set `path.parallel_safe = false` unless certified; plans inherit it (`createplan.c:1050`).
- Plan cache: dependencies are tracked for relations/functions only (`pgsrc/src/backend/utils/cache/plancache.c`); a custom path depending on extension state must register invalidation or avoid generic-plan caching.
- Re-entrancy: keep per-query state in `root->planner_cxt`, never in globals.

## 3. Design direction

Add a **CustomScan provider** in `pg_ai_core` that, for the `filter + ORDER BY <dist> LIMIT k` shape, produces one fused plan node instead of two competing paths.

- Detect the pattern and inject a `CustomPath` from `set_rel_pathlist_hook`.
- The custom node drives the existing pgvector ordered index scan as its source and applies the relational quals itself, with **adaptive over-fetch** (fetch `k * f`, grow `f` until `k` filtered rows are found or the index is exhausted) — correct top-k under filtering, without sorting the whole table.
- Cost the node so the planner actually picks it (calibrate to core cost constants).

This uses **only the public extension API** (Custom Scan + `set_rel_pathlist_hook`) and pgvector's existing ordered scan — no fork of PostgreSQL, no patch to pgvector internals.

## 4. Milestones (honest scope)

| # | Goal | API surface | Risk / effort |
|---|---|---|---|
| **M1** | Filtered ANN: relational filter + vector order + top-k with adaptive over-fetch | implemented | **DONE.** Step 1: `pg_ai_fusion` Custom Scan provider (C) — executes, chosen by planner, opt-in GUC `pg_ai_core.fuse`. Step 2: `ai.filter_ann` / `ai.filtered_search` (pg_ai 0.2.0) — over-fetch via pgvector's `hnsw.iterative_scan=strict_order`. Key insight: pgvector 0.8 already exposes the iterative-scan budget, so **no engine fork is needed** for correct filtered top-k. |
| **M2** | **Transparent** fusion: plain `WHERE quals ORDER BY emb <=> $1 LIMIT k` auto-optimized (no special function), and/or pushing the filter into the ANN traversal for better recall | planner/executor hooks (auto-enable iterative scan for the detected pattern) and/or pgvector internals (`hnswscan.c`) | High. The transparent auto-enable means manipulating `hnsw.iterative_scan` scoped to one query — do it at `ExecutorStart_hook`/`ExecutorEnd_hook` with `NewGUCNestLevel()` + `AtEOXact_GUC()` (the `auto_explain` pattern) so it never leaks to other queries. Reliable pattern detection on the plan + safe GUC scoping is the risk. Recommended as a team/contributor task. |
| **M3** | Cost model for filtered-ANN + optional native types | core costing + type system | High; this is where a team is realistically needed. |

**M1 is DONE** (filtered ANN via `ai.filter_ann`/`ai.filtered_search` + the C custom-scan foundation). **M2/M3 are real engine work that strain a solo timeline** — designed here, not built. The honest reason M1 landed without a fork: pgvector 0.8's `hnsw.iterative_scan` already provides the adaptive candidate budget that the "fusion" needs; the remaining M2 value is *transparency* (no special function) and *recall* (filter inside the graph walk), both of which warrant a contributor with PG C depth.

## 5. Risks (must-handle in M1)
1. **Costing** — within 1% fuzz the node gets dropped (`pathnode.c:52`). Calibrate `startup_cost`/`total_cost`.
2. **Correctness of top-k under filter** — over-fetch must grow until `k` filtered rows or index exhaustion; otherwise silent under-return.
3. **Parallel safety** — start `parallel_safe = false`.
4. **Plan caching** — avoid stale generic plans referencing extension state.
5. **Re-entrancy** — per-query state in `root->planner_cxt`.

## 6. Validation plan
- Correctness: fused result == `WHERE ... ORDER BY dist LIMIT k` computed by brute force on a fixture, for varying selectivity.
- Plan choice: `EXPLAIN` shows the custom node chosen for the pattern.
- Perf: fewer rows scanned vs. post-filtering at low selectivity (`EXPLAIN ANALYZE`).
- Add the above to `test/`.

## 7. Notes
Research was done against local clones at `c:\develone\pgsrc` (PostgreSQL 16) and `c:\develone\pgvector-src` (pgvector), kept out of this repo. They are the reference for implementing M1.
