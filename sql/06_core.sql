-- PostgreSQL AI Edition — pg_ai_core (V2 pilot)
-- 06: native C planner-hook extension. Loaded at startup via
-- shared_preload_libraries (see docker-compose.yml); this registers the
-- SQL-callable version function.
CREATE EXTENSION IF NOT EXISTS pg_ai_core;
