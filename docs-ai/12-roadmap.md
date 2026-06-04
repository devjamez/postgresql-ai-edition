# FASE 12 — Roadmap (V1–V5)

Grounded in what is actually shipped. Effort assumes the current setup (solo + AI assistance); "team" means it realistically needs more than one engineer.

## V1 — Thin AI database — ✅ SHIPPED (v0.1.0–v0.5.1)
Embeddings (+batch), semantic search, RAG (chunking, MMR, context budget), agents with memory, filtered ANN (over-fetch + transparent `auto_fuse` + partial-index recipe), injection-safe filters, deny-by-default RBAC, health, timeouts/retry. Native C `pg_ai_core` (planner hook, shmem telemetry, custom scan). Installable extension, CI on PG 16/17, 6 releases.
- Effort: done. Risk: low (runs on stock PG). Dependencies: pgvector, plpython3u, an Ollama/OpenAI-compatible endpoint.

## V2 — Engine-deep fusion & runtime — 🟡 partially started
- **Done:** M1 filtered ANN + M2 transparent auto-apply.
- **Next:** tools + workflows + async **agent runtime** (background worker + task queue — FASE 7/9); per-call **audit log** (FASE 10); MCP integration.
- Effort: medium–large. Risk: medium (worker isolation, queue semantics). Deps: V1. Time: months.

## V3 — Filtered ANN & cost-aware planning — 📐 designed (RFC-0002)
- In-walk predicate filtering (pgvector internals or upstream), filtered-ANN **cost model**, optional native types where ROI proven.
- Effort: large, **team** / upstream collaboration. Risk: high (silent-correctness; fork maintenance). Deps: V2. Time: quarters.

## V4 — Distribution & scale — 📐 designed (FASE 11)
- Kubernetes operator/Helm, GPU-backed model serving, multi-region read replicas, sharding strategy for very large vector sets, serverless inference integration.
- Effort: large, team + infra. Risk: medium–high. Deps: V2. Time: quarters.

## V5 — Platform — 📐 vision
- Multi-tenant managed offering, governance/observability suite, model lifecycle (versioning, evals, A/B), policy/guardrails, marketplace of agents/tools.
- Effort: company-scale. Risk: high (product + org). Deps: V3/V4 + funding/team. Time: years.

## Honest critical path
V1 is real and usable now. V2 is the next solo-feasible step (runtime/agents on the worker design). **V3 onward needs a team or upstream pgvector work** — repeatedly flagged, designed in the RFCs, not bluffed. The biggest near-term ROI is V2's agent runtime, not V3's engine surgery.
