# Kubernetes deployment

Manifests to run PostgreSQL AI Edition on Kubernetes: a `pgai` StatefulSet (the published image) + an `ollama` Deployment for local inference, in the `pg-ai` namespace.

> Status: valid manifests, **not yet exercised on a live cluster**. Treat as a starting point; review resources/storage classes/security for your environment.

## Apply

```bash
# set a real password first in 10-secret.yaml
kubectl apply -f 00-namespace.yaml
kubectl apply -f 10-secret.yaml
kubectl apply -f 20-ollama.yaml
kubectl apply -f 30-pgai.yaml

# pull the models (one time)
kubectl -n pg-ai exec deploy/ollama -- ollama pull nomic-embed-text
kubectl -n pg-ai exec deploy/ollama -- ollama pull llama3.1:8b
```

## Use

```bash
kubectl -n pg-ai exec -it statefulset/pgai -- psql -U postgres -d pgai
# the extensions auto-install on first boot; then e.g.:
#   SELECT ai.rag('...', 'docs', 'chunk', 'embedding');
```

## Notes
- **Image:** `ghcr.io/devjamez/postgresql-ai-edition:latest` is published by the `publish-image` GitHub Action (on release). Until then, build and push your own, or load a local image.
- **GPU:** for faster/larger models, schedule `ollama` on a GPU node (add `nvidia.com/gpu` limits + a runtimeClass) — DB and model server scale independently.
- **Scale:** the DB is a single-primary StatefulSet; add read replicas via streaming replication for multi-region reads (see [docs-ai/11-ai-cloud.md](../../docs-ai/11-ai-cloud.md)).
- **Secrets:** `POSTGRES_PASSWORD` (and optional `ANTHROPIC_API_KEY`) live in the `pgai-secrets` Secret — never in images or SQL.
- A managed Postgres (RDS/Cloud SQL) usually can't load `plpython3u`; this stack runs self-managed PG so the AI surface works.
