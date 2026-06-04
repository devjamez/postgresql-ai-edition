# FASE 7 — AI Runtime

The registries and engines that turn the catalog into behavior.

| Subsystem | Realization | Status |
|---|---|---|
| **Model Registry** | `ai.models` + provider layer (`ai.embed`, `ai.complete`, `ai.complete_claude`, `ai.embed_batch`) | ✅ |
| **Prompt Registry** | system prompts in `ai.agents.system_prompt`; a dedicated `ai.prompts` table | 📐 |
| **Agent Registry** | `ai.agents` + `ai.create_agent` | ✅ |
| **Memory Engine** | `ai.agent_memory` + auto-managed by `ai.call_agent` (last-N turns) | ✅ (basic; semantic memory 📐) |
| **Tool Engine** | register SQL functions as callable tools; the agent loop invokes them | 📐 (FASE 9) |
| **Workflow Engine** | multi-step orchestration (DAG of agent/tool calls) | 📐 |
| **MCP integration** | expose `ai.*` as MCP tools / consume external MCP servers | 📐 |
| **Agent-to-agent / multi-agent** | one agent calling another; orchestration | 📐 |

## Where the runtime runs

- **Today:** synchronously, inside the calling backend, via `plpython3u` HTTP calls to the model provider (Ollama local / Anthropic). Simple, transactional, no extra process.
- **Designed (for tools/workflows/async agents):** a **background worker** + **shared-memory queue** — exactly the pattern documented in [FASE 1](01-postgresql-anatomy.md) §4 (`RegisterBackgroundWorker`, `shmem_request_hook`, `BackgroundWorkerInitializeConnection`). A worker would: poll a shmem/`ai.tasks` queue, run multi-step workflows, call tools/other agents, write results back — without blocking the user's backend. `pg_ai_core` already owns the shmem machinery this needs.

## Inference location (configurable)
`OLLAMA_URL` / `AI_EMBED_MODEL` / `AI_CHAT_MODEL` / `AI_TIMEOUT` (env) select the backend. Default local Ollama (no key); optional Anthropic via `ANTHROPIC_API_KEY`. Swapping to self-hosted vLLM or other OpenAI-compatible endpoints is a provider-function change only.

## Gap summary
Built: model + agent + memory registries and the synchronous provider runtime. Designed: tools, workflows, MCP, multi-agent — all converging on the background-worker design. These are the substance of a future "AI Runtime" milestone.
