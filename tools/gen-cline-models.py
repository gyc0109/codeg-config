#!/usr/bin/env python3
"""生成 cline 的 models.json —— 否则 ACP 模式只认 gpt-4o。

cline 的模型列表**不读 providers.json**：providers.json 只决定 provider/baseUrl/apiKey，
可选模型来自同目录的 models.json。schema：

    {version:1, providers:{<providerId>:{provider:{name,baseUrl,defaultModelId},
                                        models:{<modelId>:{...}},
                                        discoveredModelIds:[...]}}}

不写它，ACP 的 model configOption 就只有 `gpt-4o`，一发请求就
`Invalid model name passed in model=gpt-4o`。

模型清单一律从 config/codebuddy/models.json 推导（那是各 agent 共用的权威副本，
含 ocg/ccg/ds/ark 四个前缀 + 上下文窗口），所以本脚本不依赖 codeg-work 中间文件。
"""
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
SRC = os.environ.get('CODEBUDDY_MODELS', os.path.join(PROJ, 'config', 'codebuddy', 'models.json'))
DST = os.environ.get('CLINE_MODELS', '/root/.cline/data/settings/models.json')

if not os.path.exists(SRC):
    sys.exit(f'✗ 找不到 {SRC}（可设 CODEBUDDY_MODELS 指定）')

src = json.load(open(SRC))
entries = src.get('models') or src
models = {}
for e in entries:
    mid = e.get('id', '')
    if not mid.startswith(('ocg/', 'ccg/', 'ds/', 'ark/')):
        continue
    models[mid] = {
        'id': mid,
        'name': e.get('name', mid),
        'contextWindow': e.get('maxInputTokens') or 131072,
        'maxTokens': e.get('maxOutputTokens') or 131072,
        'supportsReasoning': bool(e.get('supportsReasoning', True)),
        'supportsVision': bool(e.get('supportsImages', True)),
        'supportsAttachments': bool(e.get('supportsImages', True)),
        'capabilities': ['tools', 'streaming'],
    }

if not models:
    sys.exit(f'✗ {SRC} 里没有带 ocg/ccg/ds/ark 前缀的模型')

doc = {'version': 1, 'providers': {'openai-compatible': {
    'provider': {'name': 'LiteLLM (OpenAI Compatible)',
                 'baseUrl': 'http://127.0.0.1:4000/v1',
                 'defaultModelId': 'ocg/longcat-2.5-preview-free',
                 'capabilities': ['tools', 'streaming']},
    'models': models,
    'discoveredModelIds': list(models)}}}

os.makedirs(os.path.dirname(DST), exist_ok=True)
if os.path.exists(DST):
    os.rename(DST, DST + '.bak.' + str(int(time.time())))
json.dump(doc, open(DST, 'w'), indent=2, ensure_ascii=False)
os.chmod(DST, 0o600)
print(f'✓ {DST}: {len(models)} 个模型')
