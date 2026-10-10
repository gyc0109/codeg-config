#!/usr/bin/env python3
"""生成 cline 的 providers.json（provider 选择 + 端点 + key）。"""
import json, os, time

d = '/root/.cline/data/settings'
os.makedirs(d, exist_ok=True)
p = os.path.join(d, 'providers.json')
doc = {'version': 1, 'lastUsedProvider': 'openai-compatible', 'modes': {}, 'providers': {
    'openai-compatible': {'settings': {'provider': 'openai-compatible', 'apiKey': 'local',
                                        'model': 'ocg/longcat-2.5-preview-free',
                                        'baseUrl': 'http://127.0.0.1:4000/v1'},
                          'updatedAt': time.strftime('%Y-%m-%dT%H:%M:%S.000Z', time.gmtime()),
                          'tokenSource': 'manual'}}}
if os.path.exists(p):
    os.rename(p, p + '.bak.' + str(int(time.time())))
json.dump(doc, open(p, 'w'), indent=2)
os.chmod(p, 0o600)
print(f'✓ {p}')
