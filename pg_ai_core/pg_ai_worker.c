/*
 * pg_ai_worker — background worker that drains the ai.tasks queue, running each
 * task's agent asynchronously. Opt-in via pg_ai_core.enable_worker (default off).
 *
 * Design for safety: one transaction per task (claim + run + write-back), with
 * the agent call wrapped in an internal subtransaction so a failing task is
 * recorded as 'error' and never crashes the worker. If the worker dies, the
 * task simply stays 'pending' and is retried.
 */
#include "postgres.h"

#include "access/xact.h"
#include "catalog/pg_type.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "pgstat.h"
#include "postmaster/bgworker.h"
#include "postmaster/interrupt.h"
#include "storage/ipc.h"
#include "storage/latch.h"
#include "tcop/tcopprot.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include "utils/snapmgr.h"

/* GUCs defined in pg_ai_core.c */
extern char *pg_ai_task_db;
extern int	pg_ai_worker_naptime;

PGDLLEXPORT void pg_ai_worker_main(Datum main_arg) pg_attribute_noreturn();

/* Process one pending task. Returns true if a task was handled. */
static bool
process_one_task(void)
{
	bool		found = false;
	int			ret;

	SetCurrentStatementStartTimestamp();
	StartTransactionCommand();
	SPI_connect();
	PushActiveSnapshot(GetTransactionSnapshot());

	ret = SPI_execute(
		"SELECT id, agent, input FROM ai.tasks WHERE status = 'pending' "
		"ORDER BY id FOR UPDATE SKIP LOCKED LIMIT 1", false, 1);

	if (ret == SPI_OK_SELECT && SPI_processed == 1)
	{
		TupleDesc	td = SPI_tuptable->tupdesc;
		HeapTuple	row = SPI_tuptable->vals[0];
		bool		isnull;
		int64		taskid = DatumGetInt64(SPI_getbinval(row, td, 1, &isnull));
		char	   *agent = SPI_getvalue(row, td, 2);
		char	   *input = SPI_getvalue(row, td, 3);
		char	   *result = NULL;
		char	   *errm = NULL;
		bool		ok = true;
		Oid			at3[3];
		Datum		vv3[3];

		found = true;

		BeginInternalSubTransaction(NULL);
		PG_TRY();
		{
			Oid			at[2] = {TEXTOID, TEXTOID};
			Datum		vv[2];

			vv[0] = CStringGetTextDatum(agent);
			vv[1] = CStringGetTextDatum(input ? input : "");
			if (SPI_execute_with_args("SELECT ai.call_agent($1, $2)",
									  2, at, vv, NULL, false, 1) == SPI_OK_SELECT
				&& SPI_processed == 1)
				result = SPI_getvalue(SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 1);
			ReleaseCurrentSubTransaction();
		}
		PG_CATCH();
		{
			ErrorData  *ed = CopyErrorData();

			errm = pstrdup(ed->message ? ed->message : "error");
			FreeErrorData(ed);
			FlushErrorState();
			RollbackAndReleaseCurrentSubTransaction();
			ok = false;
		}
		PG_END_TRY();

		at3[0] = INT8OID; vv3[0] = Int64GetDatum(taskid);
		at3[1] = TEXTOID; vv3[1] = CStringGetTextDatum(ok ? "done" : "error");
		at3[2] = TEXTOID; vv3[2] = CStringGetTextDatum(ok ? (result ? result : "")
													     : (errm ? errm : "error"));
		SPI_execute_with_args(
			"UPDATE ai.tasks SET status = $2, output = $3, updated_at = now() WHERE id = $1",
			3, at3, vv3, NULL, false, 0);
	}

	SPI_finish();
	PopActiveSnapshot();
	CommitTransactionCommand();
	return found;
}

void
pg_ai_worker_main(Datum main_arg)
{
	pqsignal(SIGHUP, SignalHandlerForConfigReload);
	pqsignal(SIGTERM, die);
	BackgroundWorkerUnblockSignals();

	BackgroundWorkerInitializeConnection(pg_ai_task_db, NULL, 0);
	elog(LOG, "pg_ai_core: task worker started (db=%s)", pg_ai_task_db);

	/* canonical worker loop: wait at the top (worker_spi pattern) */
	for (;;)
	{
		int n;

		(void) WaitLatch(MyLatch,
						 WL_LATCH_SET | WL_TIMEOUT | WL_EXIT_ON_PM_DEATH,
						 (long) pg_ai_worker_naptime * 1000L,
						 PG_WAIT_EXTENSION);
		ResetLatch(MyLatch);
		CHECK_FOR_INTERRUPTS();		/* handles SIGTERM via die() */

		if (ConfigReloadPending)
		{
			ConfigReloadPending = false;
			ProcessConfigFile(PGC_SIGHUP);
		}

		/* process up to 10 pending tasks per wake; tolerate transient errors */
		PG_TRY();
		{
			for (n = 0; n < 10; n++)
			{
				if (!process_one_task())
					break;
				CHECK_FOR_INTERRUPTS();
			}
		}
		PG_CATCH();
		{
			EmitErrorReport();
			FlushErrorState();
			AbortOutOfAnyTransaction();
		}
		PG_END_TRY();
	}
}
