/*
 * pg_ai_fusion — V2 M1 (step 1): a Custom Scan provider.
 *
 * This is the executable skeleton for relational + vector plan fusion. For now
 * it registers a CustomScan that faithfully scans a base relation (applying the
 * query's quals and projection through the standard ExecScan machinery), proving
 * the full path -> plan -> exec wiring end to end.
 *
 * It is OPT-IN via the GUC `pg_ai_core.fuse` (default off): when on, base-table
 * scans are routed through this node. The next step layers adaptive over-fetch +
 * filtering for the "WHERE quals ORDER BY emb <=> $1 LIMIT k" pattern on top of
 * this node (see docs-ai/RFC-0001-v2-plan-fusion.md).
 *
 * Built into pg_ai_core.so; initialized from _PG_init via pg_ai_fusion_init().
 */
#include "postgres.h"

#include "access/relscan.h"
#include "access/tableam.h"
#include "catalog/pg_class.h"
#include "executor/executor.h"
#include "executor/tuptable.h"
#include "nodes/extensible.h"
#include "nodes/pathnodes.h"
#include "nodes/plannodes.h"
#include "optimizer/pathnode.h"
#include "optimizer/paths.h"
#include "optimizer/restrictinfo.h"
#include "utils/guc.h"

void		pg_ai_fusion_init(void);

static set_rel_pathlist_hook_type prev_set_rel_pathlist_hook = NULL;
static bool pg_ai_fuse = false;

/* forward decls */
static Plan *FusionPlanCustomPath(PlannerInfo *root, RelOptInfo *rel,
								  CustomPath *best_path, List *tlist,
								  List *clauses, List *custom_plans);
static Node *FusionCreateScanState(CustomScan *cscan);
static void FusionBeginScan(CustomScanState *node, EState *estate, int eflags);
static TupleTableSlot *FusionExecScan(CustomScanState *node);
static void FusionEndScan(CustomScanState *node);
static void FusionReScan(CustomScanState *node);

static CustomPathMethods fusion_path_methods = {
	.CustomName = "pg_ai_fusion",
	.PlanCustomPath = FusionPlanCustomPath,
	.ReparameterizeCustomPathByChild = NULL,
};

static CustomScanMethods fusion_scan_methods = {
	.CustomName = "pg_ai_fusion",
	.CreateCustomScanState = FusionCreateScanState,
};

static CustomExecMethods fusion_exec_methods = {
	.CustomName = "pg_ai_fusion",
	.BeginCustomScan = FusionBeginScan,
	.ExecCustomScan = FusionExecScan,
	.EndCustomScan = FusionEndScan,
	.ReScanCustomScan = FusionReScan,
};

/* ----- planner: offer a custom path for plain base relations ----- */
static void
FusionSetRelPathlist(PlannerInfo *root, RelOptInfo *rel, Index rti,
					 RangeTblEntry *rte)
{
	CustomPath *cpath;

	if (prev_set_rel_pathlist_hook)
		prev_set_rel_pathlist_hook(root, rel, rti, rte);

	if (!pg_ai_fuse)
		return;
	if (rte->rtekind != RTE_RELATION || rte->relkind != RELKIND_RELATION)
		return;
	if (rel->reloptkind != RELOPT_BASEREL)
		return;

	cpath = makeNode(CustomPath);
	cpath->path.pathtype = T_CustomScan;
	cpath->path.parent = rel;
	cpath->path.pathtarget = rel->reltarget;
	cpath->path.param_info = NULL;
	cpath->path.parallel_aware = false;
	cpath->path.parallel_safe = false;
	cpath->path.parallel_workers = 0;
	cpath->path.rows = rel->rows;
	cpath->path.startup_cost = 0;
	cpath->path.total_cost = 0;	/* force selection while fuse is on */
	cpath->path.pathkeys = NIL;
	cpath->flags = 0;
	cpath->custom_paths = NIL;
	cpath->custom_private = NIL;
	cpath->methods = &fusion_path_methods;

	add_path(rel, (Path *) cpath);
}

/* ----- path -> plan ----- */
static Plan *
FusionPlanCustomPath(PlannerInfo *root, RelOptInfo *rel,
					 CustomPath *best_path, List *tlist,
					 List *clauses, List *custom_plans)
{
	CustomScan *cscan = makeNode(CustomScan);

	cscan->scan.plan.targetlist = tlist;
	cscan->scan.plan.qual = extract_actual_clauses(clauses, false);
	cscan->scan.scanrelid = rel->relid;
	cscan->flags = best_path->flags;
	cscan->custom_plans = custom_plans;
	cscan->custom_exprs = NIL;
	cscan->custom_private = NIL;
	cscan->custom_scan_tlist = NIL;
	cscan->methods = &fusion_scan_methods;

	return &cscan->scan.plan;
}

/* ----- plan -> executor state ----- */
static Node *
FusionCreateScanState(CustomScan *cscan)
{
	CustomScanState *css = makeNode(CustomScanState);

	css->methods = &fusion_exec_methods;
	/* we read on-disk heap tuples via the table AM, so request a heap slot */
	css->slotOps = &TTSOpsBufferHeapTuple;
	return (Node *) css;
}

/* ----- executor ----- */
static TupleTableSlot *
FusionAccess(ScanState *ss)
{
	TableScanDesc scandesc = ss->ss_currentScanDesc;
	EState	   *estate = ss->ps.state;
	TupleTableSlot *slot = ss->ss_ScanTupleSlot;

	if (table_scan_getnextslot(scandesc, estate->es_direction, slot))
		return slot;
	return NULL;
}

static bool
FusionRecheck(ScanState *ss, TupleTableSlot *slot)
{
	return true;
}

static void
FusionBeginScan(CustomScanState *node, EState *estate, int eflags)
{
	node->ss.ss_currentScanDesc =
		table_beginscan(node->ss.ss_currentRelation, estate->es_snapshot, 0, NULL);
}

static TupleTableSlot *
FusionExecScan(CustomScanState *node)
{
	return ExecScan(&node->ss,
					(ExecScanAccessMtd) FusionAccess,
					(ExecScanRecheckMtd) FusionRecheck);
}

static void
FusionEndScan(CustomScanState *node)
{
	if (node->ss.ss_currentScanDesc)
		table_endscan(node->ss.ss_currentScanDesc);
}

static void
FusionReScan(CustomScanState *node)
{
	if (node->ss.ss_currentScanDesc)
		table_rescan(node->ss.ss_currentScanDesc, NULL);
}

/* ----- init (called from _PG_init) ----- */
void
pg_ai_fusion_init(void)
{
	DefineCustomBoolVariable("pg_ai_core.fuse",
							 "Route base-table scans through the pg_ai fusion custom scan (V2 M1 pilot).",
							 NULL,
							 &pg_ai_fuse,
							 false,
							 PGC_USERSET,
							 0,
							 NULL, NULL, NULL);

	RegisterCustomScanMethods(&fusion_scan_methods);

	prev_set_rel_pathlist_hook = set_rel_pathlist_hook;
	set_rel_pathlist_hook = FusionSetRelPathlist;
}
