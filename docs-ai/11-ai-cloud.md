# FASE 11 — Deployment & Cloud

How to run `pg_ai` from a laptop to a cloud cluster. Today it ships as Docker; the cloud topologies below are architecture, not yet automation.

## Today (shipped)
- **Docker Compose**: `db` (PostgreSQL 16/17 + pgvector + plpython3 + `pg_ai`/`pg_ai_core`) + `ollama` (local inference). One command up; image published to **GHCR** (`ghcr.io/devjamez/postgresql-ai-edition`).
- **Standalone**: build the extensions on any PG 16/17 (`INSTALL.md`).

## Cloud topologies (design)

| Target | Approach |
|---|---|
| **AWS / Azure / GCP (managed PG?)** | Managed PG (RDS/Cloud SQL) usually **does not allow `plpython3u`** (untrusted) → run `pg_ai` on **self-managed PG** (EC2/VM/container) or a provider that allows untrusted PLs. pgvector is available on most managed PG; the AI surface needs the untrusted language. |
| **Kubernetes** | StatefulSet for PG (+pgvector+pg_ai), a Deployment for the model server (Ollama/vLLM) with GPU node pool, a Service for `OLLAMA_URL`. Use the CloudNativePG / Zalando operators for the PG side. |
| **Multi-region** | PG streaming replication (read replicas near users); embeddings/indexes replicate with the data (they're normal relations/indexes — FASE 1 §2/§5). Writes stay single-primary. |
| **Serverless** | the DB is stateful (not serverless), but **inference** can be serverless/remote (Anthropic API, or scale-to-zero GPU endpoints) via the provider env vars. |
| **Edge** | small models (`llama3.2`, `nomic-embed-text`) run on modest hardware; `pg_ai` + local Ollama on an edge node is viable for offline/low-latency. |

## Inference scaling
The DB and the model server scale **independently**. `OLLAMA_URL` points at any OpenAI/Ollama-compatible endpoint: a sidecar, a shared GPU service, or a remote API. Batch with `ai.embed_batch`; tune `AI_TIMEOUT`.

## Operational notes
- Health: `SELECT ai.health();` (reachability + models + config).
- Telemetry: `SELECT * FROM pg_ai_core_stats();`.
- Backups: standard `pg_dump`/PITR; registry/agent tables are dumped (`pg_extension_config_dump`).

## Gap
No Helm chart / Terraform yet — these topologies are documented designs. The Docker + GHCR path is the shipped, tested deployment.
