# FASE 1 — Anatomy of PostgreSQL 16

Reference map of the PostgreSQL internals an "AI Edition" must understand before extending. Researched against the real source (`REL_16_STABLE`); citations are `path:line`. For each component: what it does, where it lives, risk of modification, performance impact, and relevance to `pg_ai`.

> Why this exists: `pg_ai`/`pg_ai_core` extend Postgres through its supported seams (extensions, hooks, index AM, background workers, shared memory). This document is the map of those seams and the machinery around them.

---

## 1. Query lifecycle: Parser → Rewriter → Planner → Executor

A SQL string flows: `raw_parser()` → **RawStmt** → `parse_analyze_*()` → **Query** → `RewriteQuery()` → **Query[]** → `planner()` → **PlannedStmt** → `ExecutorStart/Run/Finish/End` → tuples.

- **Parser** — `src/backend/parser/` (`parser.c:42 raw_parser()`, `gram.y`, `scan.l`). Tokenize + grammar → raw parse tree. Risk: high (regenerates the Bison machine); perf: ~5–10% of simple-query time, amortized by plan cache.
- **Parse analysis** — `src/backend/parser/analyze.c:107 parse_analyze_fixedparams()`, `transformStmt()`. Resolves names/types/functions against the catalog → `Query`. Hook: `post_parse_analyze_hook` (`analyze.c`).
- **Rewriter** — `src/backend/rewrite/rewriteHandler.c` (`RewriteQuery()`, `AcquireRewriteLocks()`). Applies rules, expands views, applies RLS.
- **Planner / Optimizer** — `src/backend/optimizer/plan/planner.c:274 planner()` → `standard_planner()` (`:287`); cost model `optimizer/path/costsize.c`; paths under `optimizer/path/`. Builds `RelOptInfo`/`Path`, picks cheapest → `Plan`. Risk: very high; perf: 1–5% OLTP, >50% for big joins.
- **Executor** — `src/backend/executor/execMain.c` (`ExecutorStart :128`, `Run :304`, `Finish :402`, `End :462`); per-node files `nodeSeqscan.c`, `nodeIndexscan.c`, `nodeCustom.c`, … ; expressions `execExpr*.c`. Pull-based pipeline.

**Relevance to pg_ai:** `pg_ai_core` uses `planner_hook` (`optimizer/planner.h:26`) to observe AI-semantic/fusion queries, and the **Custom Scan** node machinery (`nodeCustom.c`) for `pg_ai_fusion`. The semantic surface (`ai.rag`, `ai.filtered_search`) lives as functions evaluated by the executor, not as new grammar.

---

## 2. Storage & durability: heap, TOAST, buffers, WAL, MVCC, vacuum

- **Heap AM** — `src/backend/access/heap/heapam.c` (`heap_insert :1884`, `heap_update :3046`, `heap_delete :2577`, `heap_beginscan :985`); table-AM API `src/include/access/tableam.h`. Tuples carry `xmin/xmax` in `HeapTupleHeaderData` (`access/htup_details.h`).
- **TOAST** — `src/backend/access/heap/heaptoast.c:96 heap_toast_insert_or_update()`; detoast `access/common/detoast.c`. Compresses/externalizes attributes > ~2KB. **Vectors are varlena → TOASTable**, relevant to embedding storage.
- **Buffer manager** — `src/backend/storage/buffer/bufmgr.c` (`ReadBuffer`, `MarkBufferDirty`, clock-sweep). 8KB pages in shared memory.
- **WAL** — `src/backend/access/transam/xlog.c` (`StartupXLOG`, insertion), `xloginsert.c` (`XLogInsertRecord`). Write-ahead journal; LSN-ordered.
- **MVCC** — snapshots `src/backend/utils/time/snapmgr.c:157 GetSnapshotData()`; visibility `access/heap/heapam_visibility.c` (`HeapTupleSatisfiesMVCC`). Commit status `access/transam/clog.c`.
- **VACUUM/autovacuum** — `access/heap/vacuumlazy.c:823 lazy_scan_heap()`; daemon `postmaster/autovacuum.c`; HOT pruning `pruneheap.c`; visibility map `visibilitymap.c`.

**Relevance to pg_ai:** embeddings ride normal heap+TOAST (no special storage needed at V1); MVCC/visibility is why the `pg_ai_fusion` custom scan reads through the table AM (`table_scan_getnextslot`) with the right snapshot.

---

## 3. Catalog, types, functions, triggers

- **System catalogs** — `src/include/catalog/` (`pg_class.h`, `pg_attribute.h`, `pg_proc.h`, `pg_type.h`, `pg_am.h`, `pg_extension.h`, `*.dat`). Self-describing metadata.
- **Syscache/relcache** — `src/backend/utils/cache/syscache.c`, `catcache.c`. In-memory O(1) catalog lookups with invalidation; ~99% hit rate.
- **Type system** — `pg_type` + I/O functions; create via `src/backend/catalog/pg_type.c:345 TypeCreate()`, DDL `commands/typecmds.c`. Types are extensible (this is how a future native `VECTOR`/`AGENT` type would be added — M3).
- **Function manager (fmgr)** — `src/backend/utils/fmgr/fmgr.c`; `PG_FUNCTION_ARGS`, `FmgrInfo`/`FunctionCallInfo` in `src/include/fmgr.h`. Dispatches C/SQL/PL functions. This is the path every `ai.*` function call takes.
- **PLs** — `src/pl/` (PL/pgSQL, PL/Python). `pg_ai` providers use **untrusted `plpython3u`** for HTTP calls.
- **Triggers** — `pg_trigger.h`, `src/backend/commands/trigger.c` (`CreateTrigger`, `ExecCallTriggerFunc`). BEFORE/AFTER × ROW/STATEMENT.

**Relevance to pg_ai:** the whole `ai.*` surface is `pg_proc` entries created by the extension; `CREATE EXTENSION` auto-links them to `pg_extension` via `pg_depend`. Native AI types are a `pg_type`/`TypeCreate` exercise (deferred to M3).

---

## 4. Process model & concurrency: postmaster, shared memory, locking, background workers

- **Process model** — one process per connection. `src/backend/postmaster/postmaster.c` (`ServerLoop :1735`, `BackendStartup :4124`). Postmaster holds no locks; crashes are isolated.
- **Shared memory** — sized in `src/backend/storage/ipc/ipci.c` (`CalculateShmemSize`, `CreateSharedMemoryAndSemaphores`); allocate via `storage/ipc/shmem.c` (`ShmemInitStruct`). Extensions request space in `shmem_request_hook` (`RequestAddinShmemSpace`) and init in `shmem_startup_hook`.
- **Locking** — heavyweight lock manager `storage/lmgr/lock.c:769 LockAcquire()` (8 modes, fast-path for weak relation locks); LWLocks `storage/lmgr/lwlock.c`; spinlocks. Deadlock detector `storage/lmgr/deadlock.c`.
- **Background workers** — `src/include/postmaster/bgworker.h`, `src/backend/postmaster/bgworker.c` (`RegisterBackgroundWorker`, `RegisterDynamicBackgroundWorker`). Workers can connect to a DB and run arbitrary code.

**Relevance to pg_ai:** `pg_ai_core` already uses `shmem_request_hook`/`shmem_startup_hook` + `pg_atomic` for cluster-wide telemetry. A future in-engine inference/runtime (model serving, async agents) is exactly a **background-worker + shared-memory** design — this section is its blueprint.

---

## 5. Indexes, replication, extensions & hooks

- **Index AM API** — `src/include/access/amapi.h:210 IndexAmRoutine` (build/insert/scan/cost callbacks + capability flags like `amcanorderbyop`). Built-ins: nbtree, gin, gist, brin, spgist, hash (each a `*handler()`). Register via `CREATE ACCESS METHOD ... HANDLER`. **pgvector's HNSW/IVFFlat are exactly this**; `amcanorderbyop` is what makes `ORDER BY emb <=> q` index-ordered.
- **Replication** — physical `src/backend/replication/walsender.c`/`walreceiver.c`; logical `replication/logical/` (decode, snapbuild, reorderbuffer) with output plugins.
- **Extensions framework** — `src/backend/commands/extension.c` (control file + versioned SQL + `pg_depend`); PGXS `src/makefiles/pgxs.mk`; `_PG_init()` entry; `shared_preload_libraries`. **This is how all of `pg_ai`/`pg_ai_core` ship.**
- **Hooks (the seams we use / could use):**
  - `planner_hook` — `optimizer/planner.h:26` (used)
  - `set_rel_pathlist_hook` — `optimizer/paths.h:29` (used by `pg_ai_fusion`)
  - `ExecutorStart/Run/Finish/End_hook` — `executor/executor.h:75–91` (the safe place to scope `hnsw.iterative_scan` per query — M2 auto-apply)
  - `shmem_request_hook` / `shmem_startup_hook` — `miscadmin.h:503`, `storage/ipc.h:78` (used)
  - `get_relation_info_hook`, `ProcessUtility_hook`, `ClientAuthentication_hook`, `emit_log_hook` — other extension points.

**Relevance to pg_ai:** V1 builds entirely on the **extension + index-AM + hooks** seams (no fork). M2/M3 (transparent fusion, native types, cost model) extend deeper but along these same documented interfaces — see [RFC-0001](RFC-0001-v2-plan-fusion.md).

---

## How modification risk maps to our strategy

| Layer | Risk to modify | pg_ai approach |
|---|---|---|
| Parser/grammar | very high | **avoid** — functions, not new syntax |
| Planner internals | very high | **observe** via hooks; add paths, don't rewrite core |
| Executor nodes | very high | **add** a Custom Scan; don't touch core nodes |
| Type system | high | native types deferred to M3 (additive via `TypeCreate`) |
| Index AM | medium | **reuse** pgvector; don't reimplement |
| Extensions/hooks/bgworkers/shmem | low–medium | **build here** — the supported surface |

This is the concrete basis for the project's "extension-first, fork-never-unless-justified" stance (ADR-0001).
