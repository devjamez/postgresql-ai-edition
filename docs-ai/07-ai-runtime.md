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
- **Async runtime — ✅ SHIPPED (0.7.0):** a native-C **background worker** in `pg_ai_core` drains the `ai.tasks` queue (`ai.submit_task`/`task_status`/`task_result`), running each task's agent without blocking the user's backend — the FASE 1 §4 bgworker design (`RegisterBackgroundWorker`, `BackgroundWorkerInitializeConnection`). Opt-in via `pg_ai_core.enable_worker`. Tools and workflows (0.6.0) run synchronously today; running them *through* the queue is a small additive step on this worker.

## Inference location (configurable)
`OLLAMA_URL` / `AI_EMBED_MODEL` / `AI_CHAT_MODEL` / `AI_TIMEOUT` (env) select the backend. Default local Ollama (no key); optional Anthropic via `ANTHROPIC_API_KEY`. Swapping to self-hosted vLLM or other OpenAI-compatible endpoints is a provider-function change only.

## Gap summary
Built: model + agent + memory registries and the synchronous provider runtime. Designed: tools, workflows, MCP, multi-agent — all converging on the background-worker design. These are the substance of a future "AI Runtime" milestone.
