# FASE 10 — AI Security

| Threat | Posture in `pg_ai` | Status |
|---|---|---|
| **SQL injection (via filters)** | filters are `jsonb` equality built with `format('%I = %L')` (identifiers validated, values escaped); raw predicates isolated in `ai.filter_ann_raw` (revoked from PUBLIC) | ✅ |
| **Privilege / capability control (RBAC)** | deny-by-default: `EXECUTE` revoked from `PUBLIC` on network/raw functions (`ai.embed`, `ai.embed_batch`, `ai.complete`, `ai.complete_claude`, `ai.filter_ann_raw`, `ai.health`); DBA grants to trusted roles | ✅ |
| **Secret handling** | model keys/URLs only in the **server environment** (`.env` → container env), never in SQL or the repo; `.env` gitignored | ✅ |
| **Untrusted language exposure** | providers use `plpython3u` (untrusted) → only superusers create them; surface limited via the REVOKEs above | ✅ |
| **Prompt injection** | RAG uses a constraining system prompt ("answer only from context"); documented as a residual risk | 🟡 |
| **Data leakage to providers** | local Ollama by default = **no data leaves the host**; remote providers are opt-in (`ANTHROPIC_API_KEY`) | ✅ (local default) |
| **Tenant isolation** | inherits PostgreSQL: roles, schemas, **Row-Level Security** on the underlying tables | 🟡 (inherited; not AI-specific yet) |
| **Model / agent isolation** | synchronous calls run in the caller's backend under its privileges; a future worker runtime needs its own isolation | 📐 |
| **Encryption** | at rest via PG/storage TLS; in transit to providers via HTTPS (Anthropic) / local socket (Ollama) | 🟡 |
| **Auditing** | `pg_ai_core` telemetry (`pg_ai_core_stats`: planned / ai_intercepted / fusion_candidates); full audit log of prompts/responses | 🟡 (telemetry yes; per-call audit 📐) |

## Hardening guidance
- Grant `ai.*` deliberately; never `GRANT … TO PUBLIC` on the network functions.
- Enable RLS on tables exposed through `ai.rag`/`ai.filtered_search` so retrieval respects per-tenant visibility.
- Treat model output as untrusted; when tools land (FASE 9), allow-list them and run least-privilege.
- Keep inference local (Ollama) for sensitive data; opt into remote providers per-workload.

## Gaps (designed)
Per-call prompt/response audit log (`ai.audit` table + hook), stronger prompt-injection mitigations, and isolation for an async worker runtime. All additive; none blocks current use.
