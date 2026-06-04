# PostgreSQL AI Edition — pg_ai (thin) + pg_ai_core (V2 native C pilot)
# Base: pgvector over PostgreSQL 16, plus PL/Python (untrusted) for HTTP calls.
FROM pgvector/pgvector:pg16

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      postgresql-plpython3-16 \
      build-essential \
      postgresql-server-dev-16 \
 && rm -rf /var/lib/apt/lists/*

# Install the SQL extension (pg_ai)
COPY pg_ai/ /tmp/pg_ai/
RUN cd /tmp/pg_ai && make install && rm -rf /tmp/pg_ai

# Build & install the native C extension (pg_ai_core: planner hook + telemetry)
COPY pg_ai_core/ /tmp/pg_ai_core/
RUN cd /tmp/pg_ai_core && make && make install && rm -rf /tmp/pg_ai_core
