# FASE 9 — Agent Engine

Agents with memory, today; tools/workflows/communication, designed.

## Built

```sql
SELECT ai.create_agent('asesor', 'Sos un asesor de compras. Respondé corto.', 'llama3.1:8b');
SELECT ai.call_agent('asesor', 'busco una laptop para programar');
SELECT ai.call_agent('asesor', '¿y para jugar también?');   -- remembers the prior turn
```

- **`CREATE AGENT`** → `ai.create_agent(name, system_prompt, model)` (`ai.agents`). ✅
- **`CALL AGENT`** → `ai.call_agent(name, message)`: loads last-N turns from `ai.agent_memory`, builds the prompt, calls the model, persists both turns. ✅
- **AGENT MEMORY** → `ai.agent_memory` (per-agent, chronological). ✅ Verified: turn 2 uses turn 1's context (see [DEMO](DEMO.md) §3).

## Designed (deferred) — and the mechanism for each

| Capability | Design |
|---|---|
| **AGENT TOOLS** | register PG functions as tools in `ai.tools`; the agent loop asks the model which tool to call (function-calling), executes it, feeds the result back. Tool execution = ordinary function calls under the caller's privileges. |
| **AGENT WORKFLOWS** | a DAG of agent/tool steps in `ai.workflows`; executed step-by-step, state in a table. |
| **AGENT COMMUNICATION (A2A)** | one agent calling `ai.call_agent` on another; shared memory tables for hand-off. |
| **AGENT EVENTS / TASKS** | an `ai.tasks` queue drained by a **background worker** (FASE 1 §4 / FASE 7) for async, long-running, or scheduled agent runs — without blocking user backends. |

## Why memory-first
Memory + a clean `call_agent` loop is the irreducible core; tools/workflows/async are layers on top. Shipping the core proves the model and keeps the surface honest. The deferred pieces all converge on two primitives already designed: a **task table/queue** and a **background worker**.

## Security note
Agents run model output; treat it as untrusted. Tool execution (when added) must be allow-listed and run with least privilege. See [FASE 10](10-ai-security.md).
