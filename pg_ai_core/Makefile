MODULE_big = pg_ai_core
OBJS = pg_ai_core.o

EXTENSION = pg_ai_core
DATA = pg_ai_core--0.1.sql
PGFILEDESC = "pg_ai_core - native C planner integration pilot (V2)"

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
