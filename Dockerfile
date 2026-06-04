# PostgreSQL AI Edition — pg_ai (thin edition)
# Base: pgvector over PostgreSQL 16, plus PL/Python (untrusted) for HTTP calls.
FROM pgvector/pgvector:pg16

RUN apt-get update \
 && apt-get install -y --no-install-recommends postgresql-plpython3-16 \
 && rm -rf /var/lib/apt/lists/*
