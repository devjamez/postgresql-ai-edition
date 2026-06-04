-- PostgreSQL AI Edition — pg_ai (thin edition)
-- 01: extensions, schema, model registry

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS plpython3u;

CREATE SCHEMA IF NOT EXISTS ai;

-- Model registry (pg_ai_models)
CREATE TABLE IF NOT EXISTS ai.models (
    id         serial PRIMARY KEY,
    name       text UNIQUE NOT NULL,
    provider   text NOT NULL CHECK (provider IN ('ollama','openai','anthropic')),
    kind       text NOT NULL CHECK (kind IN ('embedding','completion')),
    model_id   text NOT NULL,
    dimensions int,
    created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO ai.models (name, provider, kind, model_id, dimensions) VALUES
    ('default-embedding',  'ollama',    'embedding',  'nomic-embed-text',  768),
    ('default-completion', 'ollama',    'completion', 'llama3.2',          NULL),
    ('claude',             'anthropic', 'completion', 'claude-sonnet-4-6', NULL)
ON CONFLICT (name) DO NOTHING;
