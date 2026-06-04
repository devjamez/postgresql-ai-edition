-- PostgreSQL AI Edition — pg_ai (thin edition)
-- 02: provider layer. Local inference via Ollama (no API key).
-- Ollama base URL + model names come from the server environment.

-- Embeddings via Ollama (default: nomic-embed-text -> vector(768))
CREATE OR REPLACE FUNCTION ai.embed(input text)
RETURNS vector
LANGUAGE plpython3u AS $$
import os, json, urllib.request, urllib.error
base  = os.environ.get('OLLAMA_URL', 'http://ollama:11434')
model = os.environ.get('AI_EMBED_MODEL', 'nomic-embed-text')
body = json.dumps({'model': model, 'prompt': input}).encode()
req = urllib.request.Request(base + '/api/embeddings', data=body, method='POST')
req.add_header('Content-Type', 'application/json')
try:
    with urllib.request.urlopen(req, timeout=120) as r:
        resp = json.loads(r.read().decode())
except urllib.error.HTTPError as e:
    plpy.error('Ollama embeddings %d: %s' % (e.code, e.read().decode()))
except urllib.error.URLError as e:
    plpy.error('Ollama unreachable at %s: %s' % (base, e.reason))
vec = resp.get('embedding')
if not vec:
    plpy.error('Ollama returned no embedding (model pulled?): %s' % json.dumps(resp)[:200])
return '[' + ','.join(repr(x) for x in vec) + ']'
$$;

-- Completion via Ollama (default: llama3.2)
CREATE OR REPLACE FUNCTION ai.complete(prompt text, system text DEFAULT NULL, model text DEFAULT NULL)
RETURNS text
LANGUAGE plpython3u AS $$
import os, json, urllib.request, urllib.error
base = os.environ.get('OLLAMA_URL', 'http://ollama:11434')
mdl  = model or os.environ.get('AI_CHAT_MODEL', 'llama3.2')
payload = {'model': mdl, 'prompt': prompt, 'stream': False}
if system:
    payload['system'] = system
body = json.dumps(payload).encode()
req = urllib.request.Request(base + '/api/generate', data=body, method='POST')
req.add_header('Content-Type', 'application/json')
try:
    with urllib.request.urlopen(req, timeout=300) as r:
        resp = json.loads(r.read().decode())
except urllib.error.HTTPError as e:
    plpy.error('Ollama generate %d: %s' % (e.code, e.read().decode()))
except urllib.error.URLError as e:
    plpy.error('Ollama unreachable at %s: %s' % (base, e.reason))
return resp.get('response', '')
$$;

-- OPTIONAL: completion via Anthropic (Claude). Requires ANTHROPIC_API_KEY.
CREATE OR REPLACE FUNCTION ai.complete_claude(prompt text, system text DEFAULT NULL,
                                              model text DEFAULT 'claude-sonnet-4-6', max_tokens int DEFAULT 1024)
RETURNS text
LANGUAGE plpython3u AS $$
import os, json, urllib.request, urllib.error
key = os.environ.get('ANTHROPIC_API_KEY')
if not key:
    plpy.error('ANTHROPIC_API_KEY not set in the database server environment')
payload = {'model': model, 'max_tokens': max_tokens, 'messages': [{'role': 'user', 'content': prompt}]}
if system:
    payload['system'] = system
body = json.dumps(payload).encode()
req = urllib.request.Request('https://api.anthropic.com/v1/messages', data=body, method='POST')
req.add_header('Content-Type', 'application/json')
req.add_header('x-api-key', key)
req.add_header('anthropic-version', '2023-06-01')
try:
    with urllib.request.urlopen(req, timeout=120) as r:
        resp = json.loads(r.read().decode())
except urllib.error.HTTPError as e:
    plpy.error('Anthropic %d: %s' % (e.code, e.read().decode()))
return ''.join(b.get('text', '') for b in resp.get('content', []))
$$;
