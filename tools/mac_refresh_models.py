#!/usr/bin/env python3
"""刷新 Mac 上 codeg 各 agent 的模型清单（与服务器同一套前缀方案）。

Mac 没有 LiteLLM：所有 agent 一律指向本机 4 上游代理 http://127.0.0.1:15825/v1
（ocg/ ccg/ ds/ ark/ 前缀由代理分流）。

服务器上探测好的模型清单从 ~/.codeg-models/ 读入。
"""
import json
import os
import re
import shutil
import time

import yaml

H = os.path.expanduser('~')
M = os.path.join(H, '.codeg-models')
PROXY = 'http://127.0.0.1:15825/v1'

OG = json.load(open(f'{M}/ocg_final_new.json'))
CC = json.load(open(f'{M}/cc_final_new.json'))
ARK = json.load(open(f'{M}/ark_ok.json'))
META = json.load(open(f'{M}/ocg_meta.json'))
CCMETA = {m['id']: m for m in (json.load(open(f'{M}/cc_models_new.json')).get('data') or [])}
CHAT, RESP = OG['chat'], OG['resp']
CCHAT, CCRESP = CC['chat_ok'], CC['resp_ok']
DS = ['deepseek-flash', 'deepseek-v4-pro']
OCG_FREE = 'longcat-2.5-preview-free'
CC_FREE = 'stealth/glyph-cluster:free'
FB = {'deepseek-flash': (1000000, 384000), 'step-5-preview-free': (1000000, 131072)}


def okey(m, name):
    return (META.get(m) or {}).get(name)


def ocx(m):
    return int(okey(m, 'ctx') or FB.get(m, (0, 0))[0] or 262144)


def omo(m):
    return int(okey(m, 'out') or FB.get(m, (0, 0))[1] or 131072)


def onm(m):
    return okey(m, 'name') or m


def ccx(m):
    return int((CCMETA.get(m) or {}).get('context_length') or 131072)


def cnm(m):
    return (CCMETA.get(m) or {}).get('name') or m


TS = time.strftime('%Y%m%d-%H%M%S')
BK = os.path.join(H, f'codeg-model-refresh-{TS}')
os.makedirs(BK, exist_ok=True)


def bk(path):
    if os.path.exists(path):
        dst = os.path.join(BK, path.replace(H + '/', '').replace('/', '__'))
        shutil.copy2(path, dst)


print(f'备份 -> {BK}\n')


def save(path, obj, mode=0o600, indent=2):
    bk(path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as fh:
        json.dump(obj, fh, indent=indent, ensure_ascii=False)
    os.chmod(path, mode)


# ── 1) pi ──
p = f'{H}/.pi/agent/models.json'
d = json.load(open(p))
bk(p)
d['providers']['ocg']['models'] = [
    {'id': m, 'name': f'OCG {onm(m)}', 'provider': 'ocg', 'baseUrl': PROXY, 'api': 'openai-completions',
     'reasoning': True, 'input': ['text', 'image'], 'contextWindow': ocx(m), 'maxTokens': omo(m),
     'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0}} for m in CHAT]
d['providers']['ccg']['models'] = [
    {'id': m, 'name': f'CCG {cnm(m)}', 'provider': 'ccg', 'baseUrl': PROXY, 'api': 'openai-completions',
     'reasoning': True, 'input': ['text', 'image'], 'contextWindow': ccx(m), 'maxTokens': 131072,
     'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0}} for m in CCHAT]
for pre, ms, cx in (('ds', DS, lambda x: 1048576), ('ark', ARK, lambda x: 262144)):
    d['providers'][pre] = {
        'name': {'ds': 'DeepSeek Official', 'ark': 'Volcengine Ark'}[pre],
        'baseUrl': PROXY, 'apiKey': 'local', 'api': 'openai-completions',
        'models': [{'id': m, 'name': f'{pre.upper()} {m}', 'provider': pre, 'baseUrl': PROXY,
                    'api': 'openai-completions', 'reasoning': True, 'input': ['text', 'image'],
                    'contextWindow': cx(m), 'maxTokens': 131072,
                    'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0}} for m in ms]}
save(p, d)
print(f'  ✓ pi: ocg {len(CHAT)} + ccg {len(CCHAT)} + ds {len(DS)} + ark {len(ARK)}')

# ── 2) opencode ──
p = f'{H}/.config/opencode/opencode.jsonc'
raw = open(p).read()
bk(p)
d = json.loads(re.sub(r'^\s*//.*$', '', raw, flags=re.M))
d['provider']['ocg'] = {'name': 'OpenCode Go', 'options': {'baseURL': PROXY, 'apiKey': 'local'},
                        'models': {m: {'name': f'OCG {onm(m)}', 'id': m,
                                       'contextWindow': ocx(m), 'maxTokens': omo(m)} for m in CHAT}}
d['provider']['ccg'] = {'name': 'Command Code GOAT', 'options': {'baseURL': PROXY, 'apiKey': 'local'},
                        'models': {m: {'name': f'CCG {cnm(m)}', 'id': m,
                                       'contextWindow': ccx(m), 'maxTokens': 131072} for m in CCHAT}}
for pre, ms, cx in (('ds', DS, lambda x: 1048576), ('ark', ARK, lambda x: 262144)):
    d['provider'][pre] = {'name': {'ds': 'DeepSeek Official', 'ark': 'Volcengine Ark'}[pre],
                          'options': {'baseURL': PROXY, 'apiKey': 'local'},
                          'models': {m: {'name': f'{pre.upper()} {m}', 'id': m, 'contextWindow': cx(m),
                                         'maxTokens': 131072} for m in ms}}
d['model'] = f'ocg/{OCG_FREE}'
d['disabled_providers'] = list(set(d.get('disabled_providers', []) + ['opencode-go']))
bk(p)
json.dump(d, open(p, 'w'), indent=2, ensure_ascii=False)
print(f'  ✓ opencode: ocg {len(CHAT)} + ccg {len(CCHAT)} + ds {len(DS)} + ark {len(ARK)}')

# ── 3) code_buddy ──
p = f'{H}/.codebuddy/models.json'
d = json.load(open(p))
bk(p)
keep = [m for m in d['models'] if not str(m.get('id', '')).startswith(('ocg/', 'ccg/', 'ds/', 'ark/'))]
add = [{'id': f'ocg/{m}', 'name': f'OCG {onm(m)}', 'url': PROXY, 'apiKey': 'local',
        'maxInputTokens': ocx(m), 'maxOutputTokens': omo(m),
        'supportsReasoning': True, 'supportsImages': True} for m in CHAT]
add += [{'id': f'ccg/{m}', 'name': f'CCG {cnm(m)}', 'url': PROXY, 'apiKey': 'local',
         'maxInputTokens': ccx(m), 'maxOutputTokens': 131072,
         'supportsReasoning': True, 'supportsImages': True} for m in CCHAT]
add += [{'id': f'ds/{m}', 'name': f'DS {m}', 'url': PROXY, 'apiKey': 'local',
         'maxInputTokens': 1048576, 'maxOutputTokens': 393216,
         'supportsReasoning': True, 'supportsImages': True} for m in DS]
add += [{'id': f'ark/{m}', 'name': f'ARK {m}', 'url': PROXY, 'apiKey': 'local',
         'maxInputTokens': 262144, 'maxOutputTokens': 32768,
         'supportsReasoning': True, 'supportsImages': True} for m in ARK]
d['models'] = add + keep
d['availableModels'] = [m['id'] for m in d['models']]
save(p, d)
print(f'  ✓ codebuddy: {len(add)} 个（+{len(keep)} 保留）')

# ── 4) open_claw ──
p = f'{H}/.openclaw/openclaw.json'
d = json.load(open(p))
bk(p)
prov = d['models']['providers']
prov['ocg'] = {'baseUrl': PROXY, 'apiKey': 'local', 'api': 'openai-completions',
               'models': [{'id': m, 'name': f'OCG {onm(m)}', 'api': 'openai-completions', 'reasoning': True,
                           'input': ['text', 'image'], 'contextWindow': ocx(m), 'maxTokens': omo(m)}
                           for m in CHAT]}
prov['ccg'] = {'baseUrl': PROXY, 'apiKey': 'local', 'api': 'openai-completions',
               'models': [{'id': m, 'name': f'CCG {cnm(m)}', 'api': 'openai-completions', 'reasoning': True,
                           'input': ['text', 'image'], 'contextWindow': ccx(m), 'maxTokens': 131072}
                           for m in CCHAT]}
prov['ds'] = {'baseUrl': PROXY, 'apiKey': 'local', 'api': 'openai-completions',
              'models': [{'id': m, 'name': f'DS {m}', 'api': 'openai-completions', 'reasoning': True,
                          'input': ['text', 'image'], 'contextWindow': 1048576, 'maxTokens': 393216}
                          for m in DS]}
prov['ark'] = {'baseUrl': PROXY, 'apiKey': 'local', 'api': 'openai-completions',
               'models': [{'id': m, 'name': f'ARK {m}', 'api': 'openai-completions', 'reasoning': True,
                           'input': ['text', 'image'], 'contextWindow': 262144, 'maxTokens': 32768}
                           for m in ARK]}
allow = {f'{pre}/{m}': {} for pre, ms in (('ocg', CHAT), ('ccg', CCHAT), ('ds', DS), ('ark', ARK)) for m in ms}
d['agents']['defaults']['models'] = allow
save(p, d)
print(f'  ✓ openclaw: ocg {len(CHAT)} + ccg {len(CCHAT)} + ds {len(DS)} + ark {len(ARK)}，allowlist {len(allow)}')

# ── 5) kimi ──
p = f'{H}/.kimi-code/config.toml'
t = open(p).read()
bk(p)
keep, skip = [], False
for ln in t.splitlines(keepends=True):
    if re.match(r'^\[models\."(ocg|ccg|ds|ark)/', ln):
        skip = True
        continue
    if ln.startswith('['):
        skip = False
    if not skip:
        keep.append(ln)
t = ''.join(keep)
t = re.sub(r'^default_model = .*$', f'default_model = "ocg/{OCG_FREE}"', t, count=1, flags=re.M)
t = re.sub(r'(default_model = )"ccg/stealth/space-bunny-alpha"', rf'\g<1>"ccg/{CC_FREE}"', t)
t = re.sub(r'^default_model = "ocg/space-bunny-free"', f'default_model = "ocg/{OCG_FREE}"', t, flags=re.M)
sec = ''.join(f'\n[models."ocg/{m}"]\nprovider = "opencode-go"\nmodel = "{m}"\nmax_context_size = {ocx(m)}\n' for m in CHAT)
sec += ''.join(f'\n[models."ccg/{m}"]\nprovider = "commandcode"\nmodel = "{m}"\nmax_context_size = {ccx(m)}\n' for m in CCHAT)
sec += ''.join(f'\n[models."ds/{m}"]\nprovider = "deepseek"\nmodel = "{m}"\nmax_context_size = 1048576\n' for m in DS)
sec += ''.join(f'\n[models."ark/{m}"]\nprovider = "ark"\nmodel = "{m}"\nmax_context_size = 262144\n' for m in ARK)
open(p, 'w').write(t.rstrip('\n') + '\n' + sec + '\n')
print(f'  ✓ kimi: ocg {len(CHAT)} + ccg {len(CCHAT)} + ds {len(DS)} + ark {len(ARK)}')

# ── 6) hermes ──
p = f'{H}/.hermes/config.yaml'
d = yaml.safe_load(open(p))
bk(p)
cp = [x for x in d.get('custom_providers', [])
      if not str(x.get('name', '')).startswith(('OCG', 'CCG', 'DS ', 'ARK'))]
for m in CHAT:
    cp.append({'name': f'OCG {onm(m)}', 'base_url': PROXY, 'api_key': 'local', 'model': m})
for m in CCHAT:
    cp.append({'name': f'CCG {cnm(m)}', 'base_url': PROXY, 'api_key': 'local', 'model': m})
for m in DS:
    cp.append({'name': f'DS {m}', 'base_url': PROXY, 'api_key': 'local', 'model': m})
for m in ARK:
    cp.append({'name': f'ARK {m}', 'base_url': PROXY, 'api_key': 'local', 'model': m})
d['custom_providers'] = cp
d['provider'] = 'custom:' + f'OCG {onm(OCG_FREE)}'.lower().replace(' ', '-')
d['model'] = OCG_FREE
bk(p)
yaml.safe_dump(d, open(p, 'w'), allow_unicode=True, sort_keys=False)
print(f'  ✓ hermes: OCG {len(CHAT)} + CCG {len(CCHAT)} + DS {len(DS)} + ARK {len(ARK)}')

# ── 7) dsh ──
p = f'{H}/.dsh/settings.yaml'
bk(p)
L = ['llm-pi-ai:', '  providers:']
for key, disp, ms, cx in (('ocg', 'OpenCode Go', CHAT, ocx), ('ccg', 'Command Code GOAT', CCHAT, ccx),
                          ('ds', 'DeepSeek Official', DS, lambda x: 1048576),
                          ('ark', 'Volcengine Ark', ARK, lambda x: 262144)):
    L += [f'    {key}:', f'      displayName: {disp}', '      api: openai-completions',
          f'      baseURL: {PROXY}', '      apiKeyEnv: DEEPSEEK_API_KEY', '      models:']
    for m in ms:
        L += [f'        - id: {key}/{m}', f'          name: {key.upper()} {m}', f'          contextWindow: {cx(m)}']
os.makedirs(os.path.dirname(p), exist_ok=True)
open(p, 'w').write('\n'.join(L) + '\n')
print(f'  ✓ dsh: ocg {len(CHAT)} ccg {len(CCHAT)} ds {len(DS)} ark {len(ARK)}')

# ── 8) cline（此前完全没配）──
cd = f'{H}/.cline/data/settings'
os.makedirs(cd, exist_ok=True)
save(os.path.join(cd, 'providers.json'), {
    'version': 1, 'lastUsedProvider': 'openai-compatible', 'modes': {}, 'providers': {
        'openai-compatible': {'settings': {'provider': 'openai-compatible', 'apiKey': 'local',
                                           'model': f'ocg/{OCG_FREE}', 'baseUrl': PROXY},
                              'updatedAt': time.strftime('%Y-%m-%dT%H:%M:%S.000Z', time.gmtime()),
                              'tokenSource': 'manual'}}})
ref = json.load(open(f'{H}/.codebuddy/models.json'))['models']
cmodels = {}
for e in ref:
    mid = e['id']
    cmodels[mid] = {'id': mid, 'name': e['name'], 'contextWindow': e.get('maxInputTokens') or 131072,
                    'maxTokens': e.get('maxOutputTokens') or 131072, 'supportsReasoning': True,
                    'supportsVision': bool(e.get('supportsImages', True)),
                    'supportsAttachments': bool(e.get('supportsImages', True)),
                    'capabilities': ['tools', 'streaming']}
save(os.path.join(cd, 'models.json'), {
    'version': 1, 'providers': {'openai-compatible': {
        'provider': {'name': 'codeg 4-upstream proxy', 'baseUrl': PROXY, 'defaultModelId': f'ocg/{OCG_FREE}',
                     'capabilities': ['tools', 'streaming']},
        'models': cmodels, 'discoveredModelIds': list(cmodels)}}})
print(f'  ✓ cline: providers.json + models.json（{len(cmodels)} 个模型）')

print('\n完成。')
