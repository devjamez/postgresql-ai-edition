# Installation

Two ways to run PostgreSQL AI Edition: **Docker** (fastest) or **standalone** (build from source on an existing PostgreSQL).

---

## Option A — Docker (recommended for trying it)

See the [README](README.md#quickstart). One command brings up PostgreSQL + pgvector + Ollama with both extensions installed.

---

## Option B — Standalone (build from source)

### 1. Prerequisites

- **PostgreSQL 16** plus development headers — `postgresql-server-dev-16`
- **pgvector** — https://github.com/pgvector/pgvector
- **PL/Python 3 (untrusted)** — `postgresql-plpython3-16`
- A C toolchain — `build-essential`
- **Ollama** running locally (or any reachable host), with the models pulled:
  ```bash
  ollama pull nomic-embed-text   # embeddings (768d)
  ollama pull llama3.1:8b        # generation (~5 GB, needs ~8 GB free RAM)
  ```

On Debian/Ubuntu:
```bash
sudo apt-get install -y postgresql-16 postgresql-server-dev-16 \
                        postgresql-plpython3-16 build-essential
# then install pgvector per its README
```

### 2. Build & install the extensions

```bash
git clone https://github.com/devjamez/postgresql-ai-edition.git
cd postgresql-ai-edition

sudo make -C pg_ai install          # SQL extension
sudo make -C pg_ai_core install     # native C extension
```

### 3. Configure the server

In `postgresql.conf`:
```conf
shared_preload_libraries = 'pg_ai_core'
```

The provider functions read configuration from the **server process environment**
(never from SQL). Set these for the PostgreSQL service — e.g. in a systemd drop-in
(`/etc/systemd/system/postgresql.service.d/pg_ai.conf`):
```ini
[Service]
Environment=OLLAMA_URL=http://localhost:11434
Environment=AI_EMBED_MODEL=nomic-embed-text
Environment=AI_CHAT_MODEL=llama3.1:8b
# Optional, only for ai.complete_claude():
# Environment=ANTHROPIC_API_KEY=...
```

Restart PostgreSQL.

### 4. Enable in your database

```sql
CREATE EXTENSION pg_ai CASCADE;   -- pulls in vector + plpython3u
CREATE EXTENSION pg_ai_core;       -- native C planner pilot
```

### 5. Verify

```sql
SELECT vector_dims(ai.embed('hello'));   -- 768
SELECT pg_ai_core_version();
SELECT * FROM pg_ai_core_stats();        -- planned | ai_intercepted
```

Then run [`examples/demo.sql`](examples/demo.sql).

---

## Security notes

- API keys / model hosts live only in the **server environment**, never in SQL or the repo.
- `ai.embed` / `ai.complete*` use the **untrusted** `plpython3u` language: only superusers
  can create them. Grant `EXECUTE` deliberately to non-superusers.
- Treat any text passed to `ai.complete` / `ai.rag` as untrusted (prompt-injection surface).
