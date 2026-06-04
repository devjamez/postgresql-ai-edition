EXTENSION = pg_ai
DATA = pg_ai--0.1.0.sql pg_ai--0.1.0--0.2.0.sql pg_ai--0.2.0--0.3.0.sql pg_ai--0.3.0--0.4.0.sql pg_ai--0.4.0--0.5.0.sql pg_ai--0.5.0--0.6.0.sql pg_ai--0.6.0--0.7.0.sql pg_ai--0.7.0--0.8.0.sql
PGFILEDESC = "pg_ai - PostgreSQL AI Edition (embeddings, semantic search, RAG, agents)"

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
