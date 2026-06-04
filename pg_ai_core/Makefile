MODULE_big = pg_ai_core
OBJS = pg_ai_core.o pg_ai_fusion.o

EXTENSION = pg_ai_core
DATA = pg_ai_core--0.1.0.sql pg_ai_core--0.1.0--0.2.0.sql
PGFILEDESC = "pg_ai_core - native C planner integration pilot (V2)"

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
