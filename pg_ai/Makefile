EXTENSION = pg_ai
DATA = pg_ai--0.1.0.sql pg_ai--0.1.0--0.2.0.sql
PGFILEDESC = "pg_ai - PostgreSQL AI Edition (embeddings, semantic search, RAG, agents)"

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
