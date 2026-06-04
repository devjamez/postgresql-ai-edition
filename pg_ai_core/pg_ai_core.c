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
} PgAiCoreShared;

static PgAiCoreShared *pgais = NULL;

/* hook chaining */
static planner_hook_type prev_planner_hook = NULL;
static shmem_request_hook_type prev_shmem_request_hook = NULL;
static shmem_startup_hook_type prev_shmem_startup_hook = NULL;

/* GUC */
static bool pg_ai_notice = true;

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

	if (prev_planner_hook)
		return prev_planner_hook(parse, query_string, cursorOptions, boundParams);
	return standard_planner(parse, query_string, cursorOptions, boundParams);
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
	}
	LWLockRelease(AddinShmemInitLock);
}

PG_FUNCTION_INFO_V1(pg_ai_core_version);
Datum
pg_ai_core_version(PG_FUNCTION_ARGS)
{
	PG_RETURN_TEXT_P(cstring_to_text(
		"pg_ai_core 0.1.0 (native C planner hook + shared-memory telemetry)"));
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

PG_FUNCTION_INFO_V1(pg_ai_core_reset);
Datum
pg_ai_core_reset(PG_FUNCTION_ARGS)
{
	if (pgais != NULL)
	{
		pg_atomic_write_u64(&pgais->planned, 0);
		pg_atomic_write_u64(&pgais->intercepted, 0);
	}
	PG_RETURN_VOID();
}

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

	prev_planner_hook = planner_hook;
	planner_hook = pg_ai_planner;

	elog(LOG, "pg_ai_core: planner hook + shmem telemetry installed");
}
