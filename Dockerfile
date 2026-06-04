# PostgreSQL AI Edition — pg_ai (thin) + pg_ai_core (V2 native C pilot)
# Base: pgvector over PostgreSQL, plus PL/Python (untrusted) for HTTP calls.
ARG PG_VERSION=16
FROM pgvector/pgvector:pg${PG_VERSION}
ARG PG_VERSION=16

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      postgresql-plpython3-${PG_VERSION} \
      build-essential \
      postgresql-server-dev-${PG_VERSION} \
 && rm -rf /var/lib/apt/lists/*

# Optional: pgTAP for the unit-test suite (off by default to keep the image lean)
ARG WITH_PGTAP=0
RUN if [ "$WITH_PGTAP" = "1" ]; then \
      apt-get update \
      && apt-get install -y --no-install-recommends postgresql-${PG_VERSION}-pgtap \
      && rm -rf /var/lib/apt/lists/*; \
    fi

# Install the SQL extension (pg_ai)
COPY pg_ai/ /tmp/pg_ai/
RUN cd /tmp/pg_ai && make install && rm -rf /tmp/pg_ai

# Build & install the native C extension (pg_ai_core: planner hook + telemetry)
COPY pg_ai_core/ /tmp/pg_ai_core/
RUN cd /tmp/pg_ai_core && make && make install && rm -rf /tmp/pg_ai_core
