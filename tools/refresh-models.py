"""模型清单刷新（2026-10-10）：OCG 38→新增 step-5-preview-free 且 qwen3.8-max 恢复；
CC 下线 space-bunny-alpha / pixel-canary 等 6 个，新增 3 个（含新免费 stealth/glyph-cluster:free）。"""
import json
import os
import re
import shutil
import time

import yaml

OG = json.load(open('/root/codeg-work/ocg_final_new.json'))
CC = json.load(open('/root/codeg-work/cc_final_new.json'))
ARK = json.load(open('/root/codeg-work/ark_ok.json'))
CHAT, RESP = OG['chat'], OG['resp']
CCHAT, CCRESP = CC['chat_ok'], CC['resp_ok']
DS = ['deepseek-flash', 'deepseek-v4-pro']
OCG_FREE = 'longcat-2.5-preview-free'
CC_FREE = 'stealth/glyph-cluster:free'      # 新的免费 stealth 模型（space-bunny-alpha 已下线）

META = json.load(open('/root/codeg-work/ocg_meta.json'))
CCMETA = {m['id']: m for m in (json.load(open('/root/codeg-work/cc_models_new.json')).get('data') or [])}
OLD_OG = {}
try:
    OLD_OG = {m['id']: m for m in json.load(open('/root/.pi/agent/models-store.json'))['opencode-go']['models']}
except Exception:
    pass
FB = {'deepseek-flash': (1000000, 384000), 'glm-5.1': (200000, 131072),
      'minimax-m2.5': (200000, 131072), 'omen-alpha': (262144, 131072),
      'step-5-preview-free': (1000000, 131072)}


def onm(m):
    return (META.get(m) or {}).get('name') or (OLD_OG.get(m) or {}).get('name') or m


def ocx(m):
    v = (META.get(m) or {}).get('ctx') or FB.get(m, (0, 0))[0] or (OLD_OG.get(m) or {}).get('contextWindow')
    return int(v or 262144)


def omo(m):
    v = (META.get(m) or {}).get('out') or FB.get(m, (0, 0))[1] or (OLD_OG.get(m) or {}).get('maxTokens')
    return int(v or 131072)


def cnm(m):
    return (CCMETA.get(m) or {}).get('name') or m


def ccx(m):
    return int((CCMETA.get(m) or {}).get('context_length') or 131072)


TS = time.strftime('%Y%m%d-%H%M%S')
BK = f'/root/codeg-work/model-refresh-bk-{TS}'
os.makedirs(BK, exist_ok=True)


def bk(p):
    if os.path.exists(p):
        shutil.copy2(p, os.path.join(BK, os.path.basename(p)))


print(f"备份 -> {BK}\n")

# ── 1) LiteLLM ──
p = '/opt/litellm/config.yaml'
bk(p)
s = open(p).read()
s = re.sub(r'- model_name: (ocg|ds|ark)/.*?(?=- model_name:|\nlitellm_settings:)', '', s, flags=re.S)
s = re.sub(r'- model_name: ccg/.*?(?=- model_name:|\nlitellm_settings:)', '', s, flags=re.S)
blk = []
for m in sorted(set(CHAT) | set(RESP)):
    blk.append(f"""- model_name: ocg/{m}
  litellm_params:
    model: openai/{m}
    api_base: http://127.0.0.1:8899/v1
    api_key: local
    additional_drop_params: &id001
        - reasoning_effort
        - reasoning
        - thinking
        - web_search_options
        - web_search
        - search_options
        - extra_body
        - service_tier
        - store
        - modalities
        - audio
        - prediction
        - parallel_tool_calls
        - stream_options
        - include
        - truncation
        - max_tool_calls
  model_info:
    id: ocg/{m}
""")
for m in CCRESP:
    blk.append(f"""- model_name: ccg/{m}
  litellm_params:
    model: openai/{m}
    api_base: https://api.commandcode.ai/provider/v1
    api_key: __CCKEY__
    additional_drop_params: *id001
  model_info:
    id: ccg/{m}
""")
for m in DS:
    blk.append(f"""- model_name: ds/{m}
  litellm_params:
    model: openai/ds/{m}
    api_base: http://127.0.0.1:8899/v1
    api_key: local
    additional_drop_params: *id001
  model_info:
    id: ds/{m}
""")
for m in ARK:
    blk.append(f"""- model_name: ark/{m}
  litellm_params:
    model: openai/ark/{m}
    api_base: http://127.0.0.1:8899/v1
    api_key: local
    additional_drop_params: *id001
  model_info:
    id: ark/{m}
""")
s = s.replace('litellm_settings:', ''.join(blk) + 'litellm_settings:', 1)
CCKEY = re.search(r'COMMANDCODE_API_KEY=(\S+)', open('/etc/commandcode-proxy.env').read()).group(1)
s = s.replace('__CCKEY__', CCKEY)
open(p, 'w').write(s)
print(f"  ✓ LiteLLM: ocg {len(set(CHAT) | set(RESP))} + ccg {len(CCRESP)} + ds {len(DS)} + ark {len(ARK)}")

# ── 2) pi ──
p = '/root/.pi/agent/models.json'
bk(p)
d = json.load(open(p))
d['providers']['ocg']['models'] = [
    {"id": m, "name": f"OCG {onm(m)}", "provider": "ocg", "baseUrl": "http://127.0.0.1:8899/v1",
     "api": "openai-completions", "reasoning": True, "input": ["text", "image"],
     "contextWindow": ocx(m), "maxTokens": omo(m),
     "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}} for m in CHAT]
d['providers']['ccg']['models'] = [
    {"id": m, "name": f"CCG {cnm(m)}", "provider": "ccg",
     "baseUrl": "https://api.commandcode.ai/provider/v1", "api": "openai-completions",
     "reasoning": True, "input": ["text", "image"], "contextWindow": ccx(m), "maxTokens": 131072,
     "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}} for m in CCHAT]
json.dump(d, open(p, 'w'), indent=2)
os.chmod(p, 0o600)
print(f"  ✓ pi: ocg {len(CHAT)} + ccg {len(CCHAT)}")

# ── 3) kimi（顺带修掉已下线的默认 ccg 模型）──
p = '/root/.kimi-code/config.toml'
bk(p)
t = open(p).read()
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
t = re.sub(r'(\[providers\.commandcode\][^\[]*?default_model = )"[^"]*"', rf'\g<1>"{CC_FREE}"', t)
sec = ''.join(f'\n[models."ocg/{m}"]\nprovider = "opencode-go"\nmodel = "{m}"\nmax_context_size = {ocx(m)}\n' for m in CHAT)
sec += ''.join(f'\n[models."ccg/{m}"]\nprovider = "commandcode"\nmodel = "{m}"\nmax_context_size = {ccx(m)}\n' for m in CCHAT)
sec += ''.join(f'\n[models."ds/{m}"]\nprovider = "deepseek"\nmodel = "{m}"\nmax_context_size = 1048576\n' for m in DS)
sec += ''.join(f'\n[models."ark/{m}"]\nprovider = "ark"\nmodel = "{m}"\nmax_context_size = 262144\n' for m in ARK)
open(p, 'w').write(t.rstrip('\n') + '\n' + sec + '\n')
print(f"  ✓ kimi: ocg {len(CHAT)} + ccg {len(CCHAT)} + ds {len(DS)} + ark {len(ARK)}，默认已修")

# ── 4) hermes（顺带去掉已下线的 CCG Space Bunny Alpha）──
p = '/root/.hermes/config.yaml'
bk(p)
d = yaml.safe_load(open(p))
cp = [x for x in d['custom_providers']
      if not str(x.get('name', '')).startswith(('OCG', 'CCG', 'DS ', 'ARK'))]
for m in CHAT:
    cp.append({"name": f"OCG {onm(m)}", "base_url": "http://127.0.0.1:8899/v1", "api_key": "local", "model": m})
for m in CCHAT:
    cp.append({"name": f"CCG {cnm(m)}", "base_url": "https://api.commandcode.ai/provider/v1", "api_key": CCKEY, "model": m})
for m in DS:
    cp.append({"name": f"DS {m}", "base_url": "http://127.0.0.1:8896/v1", "api_key": "local", "model": m})
for m in ARK:
    cp.append({"name": f"ARK {m}", "base_url": "http://127.0.0.1:8897/v1", "api_key": "local", "model": m})
d['custom_providers'] = cp
d['provider'] = 'custom:' + f"OCG {onm(OCG_FREE)}".lower().replace(' ', '-')
d['model'] = OCG_FREE
yaml.safe_dump(d, open(p, 'w'), allow_unicode=True, sort_keys=False)
print(f"  ✓ hermes: OCG {len(CHAT)} + CCG {len(CCHAT)} + DS {len(DS)} + ARK {len(ARK)}")

# ── 5) opencode ──
p = '/root/.config/opencode/opencode.jsonc'
bk(p)
d = json.loads(re.sub(r'^\s*//.*$', '', open(p).read(), flags=re.M))
d['provider']['ocg']['models'] = {
    m: {"name": f"OCG {onm(m)}", "id": m, "contextWindow": ocx(m), "maxTokens": omo(m)} for m in CHAT}
d['provider']['ccg']['models'] = {
    m: {"name": f"CCG {cnm(m)}", "id": m, "contextWindow": ccx(m), "maxTokens": 131072} for m in CCHAT}
d['model'] = f'ocg/{OCG_FREE}'
json.dump(d, open(p, 'w'), indent=2, ensure_ascii=False)
print(f"  ✓ opencode: ocg {len(CHAT)} + ccg {len(CCHAT)}")

# ── 6) codebuddy ──
p = '/root/.codebuddy/models.json'
bk(p)
d = json.load(open(p))
keep = [m for m in d['models'] if not str(m.get('id', '')).startswith(('ocg/', 'ccg/', 'ds/', 'ark/'))]
add = [{"id": f"ocg/{m}", "name": f"OCG {onm(m)}", "url": "http://127.0.0.1:4000/v1", "apiKey": "local",
        "maxInputTokens": ocx(m), "maxOutputTokens": omo(m), "supportsReasoning": True, "supportsImages": True} for m in CHAT]
add += [{"id": f"ccg/{m}", "name": f"CCG {cnm(m)}", "url": "http://127.0.0.1:4000/v1", "apiKey": "local",
         "maxInputTokens": ccx(m), "maxOutputTokens": 131072, "supportsReasoning": True, "supportsImages": True} for m in CCHAT]
add += [{"id": f"ds/{m}", "name": f"DS {m}", "url": "http://127.0.0.1:4000/v1", "apiKey": "local",
         "maxInputTokens": 1048576, "maxOutputTokens": 393216, "supportsReasoning": True, "supportsImages": True} for m in DS]
add += [{"id": f"ark/{m}", "name": f"ARK {m}", "url": "http://127.0.0.1:4000/v1", "apiKey": "local",
         "maxInputTokens": 262144, "maxOutputTokens": 32768, "supportsReasoning": True, "supportsImages": True} for m in ARK]
d['models'] = add + keep
d['availableModels'] = [m['id'] for m in d['models']]
json.dump(d, open(p, 'w'), indent=2, ensure_ascii=False)
print(f"  ✓ codebuddy: {len(add)} 个（ocg {len(CHAT)} ccg {len(CCHAT)} ds {len(DS)} ark {len(ARK)}）")

# ── 7) openclaw ──
p = '/root/.openclaw/openclaw.json'
bk(p)
d = json.load(open(p))
d['models']['providers']['ocg'] = {
    "baseUrl": "http://127.0.0.1:8899/v1", "apiKey": "local", "api": "openai-completions",
    "models": [{"id": m, "name": f"OCG {onm(m)}", "api": "openai-completions", "reasoning": True,
                "input": ["text", "image"], "contextWindow": ocx(m), "maxTokens": omo(m)} for m in CHAT]}
d['models']['providers']['ccg'] = {
    "baseUrl": "https://api.commandcode.ai/provider/v1", "apiKey": CCKEY, "api": "openai-completions",
    "models": [{"id": m, "name": f"CCG {cnm(m)}", "api": "openai-completions", "reasoning": True,
                "input": ["text", "image"], "contextWindow": ccx(m), "maxTokens": 131072} for m in CCHAT]}
allow = {}
for m in CHAT:
    allow[f'ocg/{m}'] = {}
for m in CCHAT:
    allow[f'ccg/{m}'] = {}
for m in DS:
    allow[f'ds/{m}'] = {}
for m in ARK:
    allow[f'ark/{m}'] = {}
d['agents']['defaults']['models'] = allow
json.dump(d, open(p, 'w'), indent=2, ensure_ascii=False)
os.chmod(p, 0o600)
print(f"  ✓ openclaw: 目录 ocg {len(CHAT)} ccg {len(CCHAT)}，allowlist {len(allow)}")

# ── 8) dsh ──
p = '/root/.dsh/settings.yaml'
bk(p)
U = {'ocg': 'http://127.0.0.1:4000/v1', 'ccg': 'http://127.0.0.1:4000/v1',
     'ds': 'http://127.0.0.1:4000/v1', 'ark': 'http://127.0.0.1:4000/v1'}
L = ['# DeepSeek Harness 的模型路由（由 codeg 配置项目生成）', '#', 'llm-pi-ai:', '  providers:']
for key, disp, ms, ctxf in (('ocg', 'OpenCode Go', CHAT, ocx),
                            ('ccg', 'Command Code GOAT', CCHAT, ccx),
                            ('ds', 'DeepSeek Official', DS, lambda x: 1048576),
                            ('ark', 'Volcengine Ark', ARK, lambda x: 262144)):
    L += [f'    {key}:', f'      displayName: {disp}', '      api: openai-completions',
          f'      baseURL: {U[key]}', '      apiKeyEnv: DEEPSEEK_API_KEY', '      models:']
    for m in ms:
        L += [f'        - id: {key}/{m}', f'          name: {key.upper()} {m}', f'          contextWindow: {ctxf(m)}']
open(p, 'w').write('\n'.join(L) + '\n')
print(f"  ✓ dsh: ocg {len(CHAT)} ccg {len(CCHAT)} ds {len(DS)} ark {len(ARK)}")

# ── 9) codex catalog ──
p = '/root/.codex/codeg-model-catalog.json'
bk(p)
old = json.load(open(p))
tpl = json.loads(json.dumps(old['models'][0]))
items = []
for pre, ms in (('ocg', RESP), ('ccg', CCRESP), ('ds', DS), ('ark', ARK)):
    for m in ms:
        e = json.loads(json.dumps(tpl))
        e['slug'] = f'{pre}/{m}'
        e['display_name'] = f'{pre.upper()} {m}'
        e['description'] = e['display_name']
        e['supported_in_api'] = True
        items.append(e)
old['models'] = items
json.dump(old, open(p, 'w'), ensure_ascii=False, indent=2)
print(f"  ✓ codex catalog: {len(items)}（ocg {len(RESP)} ccg {len(CCRESP)} ds {len(DS)} ark {len(ARK)}）")

print("\n完成。")
