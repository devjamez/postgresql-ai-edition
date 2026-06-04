-- PostgreSQL AI Edition — pg_ai (thin edition)
-- 02: provider layer. HTTP calls to model APIs via PL/Python (stdlib only).
-- API keys are read from the SERVER ENVIRONMENT, never from SQL or the repo.

-- Embeddings (OpenAI text-embedding-3-small -> vector(1536))
CREATE OR REPLACE FUNCTION ai.embed(input text)
RETURNS vector
LANGUAGE plpython3u AS $$
import os, json, urllib.request, urllib.error
key = os.environ.get('OPENAI_API_KEY')
if not key:
    plpy.error('OPENAI_API_KEY not set in the database server environment')
body = json.dumps({'model': 'text-embedding-3-small', 'input': input}).encode()
req = urllib.request.Request('https://api.openai.com/v1/embeddings', data=body, method='POST')
req.add_header('Content-Type', 'application/json')
req.add_header('Authorization', 'Bearer ' + key)
try:
    with urllib.request.urlopen(req, timeout=60) as r:
        resp = json.loads(r.read().decode())
except urllib.error.HTTPError as e:
    plpy.error('OpenAI embeddings %d: %s' % (e.code, e.read().decode()))
vec = resp['data'][0]['embedding']
return '[' + ','.join(repr(x) for x in vec) + ']'
$$;

-- Completion via OpenAI chat
CREATE OR REPLACE FUNCTION ai.complete(prompt text, system text DEFAULT NULL, model text DEFAULT 'gpt-4o-mini')
RETURNS text
LANGUAGE plpython3u AS $$
import os, json, urllib.request, urllib.error
key = os.environ.get('OPENAI_API_KEY')
if not key:
    plpy.error('OPENAI_API_KEY not set in the database server environment')
msgs = []
if system:
    msgs.append({'role': 'system', 'content': system})
msgs.append({'role': 'user', 'content': prompt})
body = json.dumps({'model': model, 'messages': msgs}).encode()
req = urllib.request.Request('https://api.openai.com/v1/chat/completions', data=body, method='POST')
req.add_header('Content-Type', 'application/json')
req.add_header('Authorization', 'Bearer ' + key)
try:
    with urllib.request.urlopen(req, timeout=120) as r:
        resp = json.loads(r.read().decode())
except urllib.error.HTTPError as e:
    plpy.error('OpenAI chat %d: %s' % (e.code, e.read().decode()))
return resp['choices'][0]['message']['content']
$$;

-- Completion via Anthropic (Claude). Requires ANTHROPIC_API_KEY.
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
