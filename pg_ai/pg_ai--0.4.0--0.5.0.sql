-- pg_ai 0.4.0 -> 0.5.0
-- Operational: ai.health() reports provider reachability, models and config.
\echo Use "ALTER EXTENSION pg_ai UPDATE TO '0.5.0'" to load this file. \quit

CREATE FUNCTION ai.health()
RETURNS jsonb
LANGUAGE plpython3u AS $$
import os, json, urllib.request
base = os.environ.get('OLLAMA_URL', 'http://ollama:11434')
out = {
    'ollama_url':  base,
    'embed_model': os.environ.get('AI_EMBED_MODEL', 'nomic-embed-text'),
    'chat_model':  os.environ.get('AI_CHAT_MODEL', 'llama3.1:8b'),
    'anthropic_key_set': bool(os.environ.get('ANTHROPIC_API_KEY')),
}
try:
    with urllib.request.urlopen(base + '/api/tags', timeout=10) as r:
        tags = json.loads(r.read().decode())
    out['reachable'] = True
    out['models'] = sorted(m.get('name') for m in tags.get('models', []))
    out['embed_model_present'] = any(out['embed_model'] in (m or '') for m in out['models'])
    out['chat_model_present']  = any(out['chat_model'] in (m or '') for m in out['models'])
except Exception as e:
    out['reachable'] = False
    out['error'] = str(e)
return json.dumps(out)
$$;

-- Network function: deny-by-default like the other providers.
REVOKE ALL ON FUNCTION ai.health() FROM PUBLIC;
