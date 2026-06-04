-- PostgreSQL AI Edition — first-boot initialization
-- Installs both extensions. CASCADE pulls in vector + plpython3u for pg_ai.
CREATE EXTENSION IF NOT EXISTS pg_ai CASCADE;
CREATE EXTENSION IF NOT EXISTS pg_ai_core;
