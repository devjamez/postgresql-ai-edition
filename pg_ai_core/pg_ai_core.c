/*
 * pg_ai_core — V2 pilot: native C planner integration for PostgreSQL AI Edition.
 *
 * Installs a planner_hook so the engine can recognize AI-semantic queries at
 * plan time. This is the foundational mechanism for V2 (relational + vector
 * plan fusion). The pilot only *detects* and annotates; rewriting the plan is
 * the next milestone.
 */
#include "postgres.h"
#include "fmgr.h"
#include "optimizer/planner.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include <string.h>

PG_MODULE_MAGIC;

/* chain to any previously installed planner hook */
static planner_hook_type prev_planner_hook = NULL;

/* GUC: pg_ai_core.notice — emit a NOTICE when an AI query is detected */
static bool pg_ai_notice = true;

static bool
query_is_ai_semantic(const char *query_string)
{
	if (query_string == NULL)
		return false;

	return (strstr(query_string, "semantic_match") != NULL ||
			strstr(query_string, "ai.embed") != NULL ||
			strstr(query_string, "ai.rag") != NULL ||
			strstr(query_string, "ai.call_agent") != NULL);
}

static PlannedStmt *
pg_ai_planner(Query *parse, const char *query_string,
			  int cursorOptions, ParamListInfo boundParams)
{
	PlannedStmt *result;

	if (pg_ai_notice && query_is_ai_semantic(query_string))
		elog(NOTICE, "pg_ai_core: AI-semantic query intercepted at planner level");

	/* delegate to the previous hook or the standard planner */
	if (prev_planner_hook)
		result = prev_planner_hook(parse, query_string, cursorOptions, boundParams);
	else
		result = standard_planner(parse, query_string, cursorOptions, boundParams);

	return result;
}

PG_FUNCTION_INFO_V1(pg_ai_core_version);
Datum
pg_ai_core_version(PG_FUNCTION_ARGS)
{
	PG_RETURN_TEXT_P(cstring_to_text("pg_ai_core 0.1 (native C planner-hook pilot)"));
}

void _PG_init(void);

void
_PG_init(void)
{
	DefineCustomBoolVariable("pg_ai_core.notice",
							 "Emit a NOTICE when an AI-semantic query is intercepted.",
							 NULL,
							 &pg_ai_notice,
							 true,
							 PGC_USERSET,
							 0,
							 NULL, NULL, NULL);

	prev_planner_hook = planner_hook;
	planner_hook = pg_ai_planner;

	elog(LOG, "pg_ai_core: planner hook installed");
}
