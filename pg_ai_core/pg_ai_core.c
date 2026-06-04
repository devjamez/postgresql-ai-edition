/*
 * pg_ai_core — V2 pilot: native C planner integration for PostgreSQL AI Edition.
 *
 * Installs a planner_hook so the engine recognizes AI-semantic queries at plan
 * time (foundation for relational + vector plan fusion), and keeps cluster-wide
 * telemetry of AI workload in shared memory (counts of planned vs. intercepted
 * statements). This is the kind of native-engine integration V2 is about.
 *
 * Must be loaded via shared_preload_libraries (needs shared memory).
 */
#include "postgres.h"
#include "fmgr.h"
#include "executor/executor.h"
#include "miscadmin.h"
#include "optimizer/planner.h"
#include "port/atomics.h"
#include "storage/ipc.h"
#include "storage/lwlock.h"
#include "storage/shmem.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include <string.h>

PG_MODULE_MAGIC;

/* Cluster-wide telemetry, lives in shared memory. */
typedef struct PgAiCoreShared
{
	pg_atomic_uint64 planned;		/* total statements planned */
	pg_atomic_uint64 intercepted;	/* AI-semantic statements intercepted */
	pg_atomic_uint64 fusion;		/* filtered-ANN fusion candidates seen */
} PgAiCoreShared;

static PgAiCoreShared *pgais = NULL;

/* hook chaining */
static planner_hook_type prev_planner_hook = NULL;
static shmem_request_hook_type prev_shmem_request_hook = NULL;
static shmem_startup_hook_type prev_shmem_startup_hook = NULL;
static ExecutorStart_hook_type prev_ExecutorStart_hook = NULL;

/* GUCs */
static bool pg_ai_notice = true;
static bool pg_ai_auto_fuse = false;

static bool
query_is_ai_semantic(const char *q)
{
	if (q == NULL)
		return false;

	return (strstr(q, "semantic_match") != NULL ||
			strstr(q, "ai.embed") != NULL ||
			strstr(q, "ai.rag") != NULL ||
			strstr(q, "ai.call_agent") != NULL);
}

/*
 * Heuristic detection of the relational-filter + vector-order + limit pattern
 * (the target of transparent plan fusion). Read-only: used only for telemetry.
 */
static bool
query_is_fusion_candidate(const char *q)
{
	if (q == NULL)
		return false;

	if (strstr(q, "<=>") == NULL && strstr(q, "<->") == NULL && strstr(q, "<#>") == NULL)
		return false;

	return (strcasestr(q, "where") != NULL && strcasestr(q, "limit") != NULL);
}

static PlannedStmt *
pg_ai_planner(Query *parse, const char *query_string,
			  int cursorOptions, ParamListInfo boundParams)
{
	if (pgais != NULL)
		pg_atomic_fetch_add_u64(&pgais->planned, 1);

	if (query_is_ai_semantic(query_string))
	{
		if (pgais != NULL)
			pg_atomic_fetch_add_u64(&pgais->intercepted, 1);
		if (pg_ai_notice)
			elog(NOTICE, "pg_ai_core: AI-semantic query intercepted at planner level");
	}

	if (pgais != NULL && query_is_fusion_candidate(query_string))
		pg_atomic_fetch_add_u64(&pgais->fusion, 1);

	if (prev_planner_hook)
		return prev_planner_hook(parse, query_string, cursorOptions, boundParams);
	return standard_planner(parse, query_string, cursorOptions, boundParams);
}

/*
 * M2 auto-apply (opt-in via pg_ai_core.auto_fuse): for a detected filtered-ANN
 * query, transparently turn on iterative ANN scans so a selective filter still
 * returns the full top-k. Uses a TRANSACTION-LOCAL GUC set (auto-reverts at end
 * of transaction) — no manual restore, no leak across transactions.
 */
static void
pg_ai_ExecutorStart(QueryDesc *queryDesc, int eflags)
{
	if (prev_ExecutorStart_hook)
		prev_ExecutorStart_hook(queryDesc, eflags);
	else
		standard_ExecutorStart(queryDesc, eflags);

	if (pg_ai_auto_fuse &&
		queryDesc->sourceText != NULL &&
		query_is_fusion_candidate(queryDesc->sourceText) &&
		GetConfigOption("hnsw.iterative_scan", true, false) != NULL)
	{
		(void) set_config_option("hnsw.iterative_scan", "strict_order",
								 PGC_USERSET, PGC_S_SESSION,
								 GUC_ACTION_LOCAL, true, 0, false);
	}
}

static void
pg_ai_shmem_request(void)
{
	if (prev_shmem_request_hook)
		prev_shmem_request_hook();

	RequestAddinShmemSpace(MAXALIGN(sizeof(PgAiCoreShared)));
}

static void
pg_ai_shmem_startup(void)
{
	bool		found;

	if (prev_shmem_startup_hook)
		prev_shmem_startup_hook();

	LWLockAcquire(AddinShmemInitLock, LW_EXCLUSIVE);
	pgais = ShmemInitStruct("pg_ai_core", sizeof(PgAiCoreShared), &found);
	if (!found)
	{
		pg_atomic_init_u64(&pgais->planned, 0);
		pg_atomic_init_u64(&pgais->intercepted, 0);
		pg_atomic_init_u64(&pgais->fusion, 0);
	}
	LWLockRelease(AddinShmemInitLock);
}

PG_FUNCTION_INFO_V1(pg_ai_core_version);
Datum
pg_ai_core_version(PG_FUNCTION_ARGS)
{
	PG_RETURN_TEXT_P(cstring_to_text(
		"pg_ai_core 0.2.0 (native C planner hook + shared-memory telemetry + fusion detection)"));
}

PG_FUNCTION_INFO_V1(pg_ai_core_planned);
Datum
pg_ai_core_planned(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT64(pgais ? (int64) pg_atomic_read_u64(&pgais->planned) : 0);
}

PG_FUNCTION_INFO_V1(pg_ai_core_intercepted);
Datum
pg_ai_core_intercepted(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT64(pgais ? (int64) pg_atomic_read_u64(&pgais->intercepted) : 0);
}

PG_FUNCTION_INFO_V1(pg_ai_core_fusion_candidates);
Datum
pg_ai_core_fusion_candidates(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT64(pgais ? (int64) pg_atomic_read_u64(&pgais->fusion) : 0);
}

PG_FUNCTION_INFO_V1(pg_ai_core_reset);
Datum
pg_ai_core_reset(PG_FUNCTION_ARGS)
{
	if (pgais != NULL)
	{
		pg_atomic_write_u64(&pgais->planned, 0);
		pg_atomic_write_u64(&pgais->intercepted, 0);
		pg_atomic_write_u64(&pgais->fusion, 0);
	}
	PG_RETURN_VOID();
}

/* defined in pg_ai_fusion.c */
extern void pg_ai_fusion_init(void);

void _PG_init(void);

void
_PG_init(void)
{
	/* shared memory requires being loaded at server start */
	if (!process_shared_preload_libraries_in_progress)
		return;

	DefineCustomBoolVariable("pg_ai_core.notice",
							 "Emit a NOTICE when an AI-semantic query is intercepted.",
							 NULL,
							 &pg_ai_notice,
							 true,
							 PGC_USERSET,
							 0,
							 NULL, NULL, NULL);

	prev_shmem_request_hook = shmem_request_hook;
	shmem_request_hook = pg_ai_shmem_request;
	prev_shmem_startup_hook = shmem_startup_hook;
	shmem_startup_hook = pg_ai_shmem_startup;

	DefineCustomBoolVariable("pg_ai_core.auto_fuse",
							 "Transparently enable iterative ANN scans for detected filtered-vector queries.",
							 NULL,
							 &pg_ai_auto_fuse,
							 false,
							 PGC_USERSET,
							 0,
							 NULL, NULL, NULL);

	prev_planner_hook = planner_hook;
	planner_hook = pg_ai_planner;

	prev_ExecutorStart_hook = ExecutorStart_hook;
	ExecutorStart_hook = pg_ai_ExecutorStart;

	/* register the V2 fusion custom-scan provider */
	pg_ai_fusion_init();

	elog(LOG, "pg_ai_core: planner hook + shmem telemetry + fusion provider installed");
}
