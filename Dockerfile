# PostgreSQL AI Edition — pg_ai (thin edition) + pg_ai_core (V2 C pilot)
# Base: pgvector over PostgreSQL 16, plus PL/Python (untrusted) for HTTP calls.
FROM pgvector/pgvector:pg16

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      postgresql-plpython3-16 \
      build-essential \
      postgresql-server-dev-16 \
 && rm -rf /var/lib/apt/lists/*

# Build & install the native C pilot extension (planner-hook integration)
COPY pg_ai_core/ /tmp/pg_ai_core/
RUN cd /tmp/pg_ai_core && make && make install && rm -rf /tmp/pg_ai_core
