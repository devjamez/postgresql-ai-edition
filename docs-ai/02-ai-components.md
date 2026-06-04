# FASE 2 — AI components, types and SQL surface

Maps the original vision (AI catalog, native types, new SQL commands) to what `pg_ai` actually ships. Legend: ✅ built · 🟡 partial · 📐 designed/deferred.

## AI Catalog (system tables, schema `ai`)

| Proposed | Reality in `pg_ai` | Status |
|---|---|---|
| `pg_ai_models` | `ai.models` (registry: provider, kind, model_id, dimensions) | ✅ |
| `pg_ai_embeddings` | embeddings live in **user tables** as `vector` columns (pgvector), not a central table — the right call for relational locality | ✅ (by design) |
| `pg_ai_agents` | `ai.agents` | ✅ |
| `pg_ai_memory` | `ai.agent_memory` | ✅ |
| `pg_ai_prompts` | — | 📐 (system prompts live inline / in `ai.agents.system_prompt`) |
| `pg_ai_tools` | — | 📐 (FASE 9) |
| `pg_ai_workflows` | — | 📐 (FASE 9) |
| `pg_ai_vector_indexes` | pgvector indexes are normal PG indexes (`pg_class`/`pg_index`) — no parallel catalog needed | ✅ (by design) |

## Native types

| Proposed | Reality | Status |
|---|---|---|
| `VECTOR` | pgvector's `vector` (first-class type) | ✅ (reused, not reinvented) |
| `EMBEDDING` | = `vector` | ✅ |
| `DOCUMENT` | `text` / `jsonb` columns | ✅ (by design) |
| `PROMPT`, `AGENT`, `MEMORY`, `WORKFLOW`, `TOOL` | modeled as **rows** (`ai.agents`, `ai.agent_memory`) not as native C types | 📐 native types deferred — see RFC-0001 §8 (pgvector's `vector` suffices; bespoke types are speculative until the agent engine matures) |

## New SQL surface

The original proposed new **keywords** (`CREATE MODEL`, `CREATE AGENT`, `AI_ASK()`…). We deliberately ship **functions/operators, not grammar** (no parser fork → full compatibility):

| Proposed | Shipped | Status |
|---|---|---|
| `CREATE MODEL` | `INSERT INTO ai.models` (registry) | ✅ |
| `CREATE AGENT` | `ai.create_agent(name, system_prompt, model)` | ✅ |
| `CREATE MEMORY` | `ai.agent_memory` (auto-managed by `ai.call_agent`) | ✅ |
| `CREATE WORKFLOW` | — | 📐 |
| `AI_ASK()` | `ai.rag(...)` / `ai.complete(...)` | ✅ |
| `AI_SEARCH()` | `ai.filter_ann` / `ai.filtered_search` / `ai.semantic_match` | ✅ |
| `AI_SUMMARIZE()` | `ai.complete('summarize: '||text)` | ✅ (via complete) |
| `AI_EMBED()` | `ai.embed` / `ai.embed_batch` | ✅ |
| `AI_RAG()` | `ai.rag` | ✅ |
| `AI_EXECUTE()` | `ai.call_agent` | 🟡 (agent call; tool execution 📐) |

**Decision (ADR-0001):** functions over keywords. A semantic keyword layer would require forking `gram.y`, breaking compatibility — rejected. The full surface is available today on stock PostgreSQL.
