#!/usr/bin/env python3
"""修复 Mac 上 codeg 的 provider 与 agent env（失效模型 + ds/ark 补齐）。

通过 codeg 本地 API（127.0.0.1:3080）操作，与 UI 同路径。
"""
import json
import os
import sqlite3
import urllib.request

H = os.path.expanduser('~')
DB = f'{H}/Library/Application Support/app.codeg/codeg.db'
TOKEN = 'd1026ea824134bc0811e296bf59e644f'
API = 'http://127.0.0.1:3080/api'
PROXY = 'http://127.0.0.1:15825/v1'
OCG_FREE = 'ocg/longcat-2.5-preview-free'


def rpc(method, params):
    req = urllib.request.Request(
        f'{API}/{method}', data=json.dumps(params).encode(),
        headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + TOKEN})
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            return r.read().decode()[:200]
    except Exception as e:
        return f'ERR {type(e).__name__}: {str(e)[:120]}'


con = sqlite3.connect(DB)
con.row_factory = sqlite3.Row
rows = {r['id']: dict(r) for r in con.execute('SELECT * FROM model_provider')}

print('═══ 1) 修复 provider ═══')

# #3 claude_code CCG：五个槽位改成按角色分配（与服务器一致）
ccg_slots = {
    'main': 'ccg/z-ai/glm-5.3-flash',
    'reasoning': 'ccg/deepseek/deepseek-v4.1-flash',
    'haiku': 'ccg/deepseek/deepseek-v4.1-flash',
    'sonnet': 'ccg/z-ai/glm-5.3-flash',
    'opus': 'ccg/xiaomi/mimo-v2.6-pro',
    'customOption': 'ccg/gpt-6-luna',
    'customOptionName': 'CCG GPT-6 Luna',
    'customOptionDescription': 'Command Code GOAT · 备用均衡模型',
}
r3 = rows[3]
print('  #3 claude_code CCG:',
      rpc('update_model_provider', {'id': 3, 'agentType': r3['agent_type'], 'name': r3['name'],
                                    'apiUrl': r3['api_url'], 'apiKey': r3['api_key'],
                                    'model': json.dumps(ccg_slots, ensure_ascii=False)}))

# #5 / #7 失效模型
for pid in (5, 7):
    r = rows[pid]
    print(f'  #{pid} {r["agent_type"]} OCG:',
          rpc('update_model_provider', {'id': pid, 'agentType': r['agent_type'], 'name': r['name'],
                                        'apiUrl': r['api_url'], 'apiKey': r['api_key'],
                                        'model': OCG_FREE}))

print()
print('═══ 2) 新增 ds / ark provider ═══')
M = f'{H}/.codeg-models'
og = json.load(open(f'{M}/ocg_final_new.json'))
cc = json.load(open(f'{M}/cc_final_new.json'))
DS_M = json.dumps({'main': 'ds/deepseek-flash', 'reasoning': 'ds/deepseek-v4-pro',
                   'haiku': 'ds/deepseek-flash', 'sonnet': 'ds/deepseek-v4-pro',
                   'opus': 'ds/deepseek-v4-pro', 'customOption': 'ds/deepseek-v4-pro',
                   'customOptionName': 'DS DeepSeek V4 Pro',
                   'customOptionDescription': 'DeepSeek 官方'}, ensure_ascii=False)
ARK_M = json.dumps({'main': 'ark/doubao-seed-2-1-pro-260915', 'reasoning': 'ark/glm-5-3-flash-260828',
                    'haiku': 'ark/doubao-seed-2-1-lite-260915', 'sonnet': 'ark/doubao-seed-2-1-pro-260628',
                    'opus': 'ark/deepseek-v4-pro-ga-260813',
                    'customOption': 'ark/glm-5-3-flash-260828', 'customOptionName': 'ARK GLM 5.3 Flash',
                    'customOptionDescription': '火山方舟'}, ensure_ascii=False)

existing = {(r['agent_type'], r['name']) for r in rows.values()}
for at in ('claude_code', 'codex', 'deepseek', 'grok', 'kimi_code', 'cline', 'code_buddy'):
    if (at, 'DeepSeek Official (ds/)') not in existing:
        print(f'  + {at} ds:', rpc('create_model_provider', {
            'agentType': at, 'name': 'DeepSeek Official (ds/)', 'apiUrl': PROXY,
            'apiKey': 'local', 'model': DS_M}))
    if (at, 'Volcengine Ark (ark/)') not in existing:
        print(f'  + {at} ark:', rpc('create_model_provider', {
            'agentType': at, 'name': 'Volcengine Ark (ark/)', 'apiUrl': PROXY,
            'apiKey': 'local', 'model': ARK_M}))

print()
print('═══ 3) 修复 agent env（失效模型）═══')
ENVS = {
    'deepseek': {'DEEPSEEK_ACP_MODEL': 'ocg/longcat-2.5-preview-free', 'DEEPSEEK_ACP_PROVIDER': 'ocg',
                 'DEEPSEEK_BASE_URL': PROXY, 'DEEPSEEK_API_KEY': 'local'},
    'code_buddy': {'CODEBUDDY_MODEL': 'ocg/longcat-2.5-preview-free', 'CODEBUDDY_BASE_URL': PROXY,
                   'CODEBUDDY_API_KEY': 'local', 'CODEBUDDY_DISABLE_BUILTIN_MODELS': '1'},
    'kimi_code': {'KIMI_MODEL_NAME': 'longcat-2.5-preview-free', 'KIMI_MODEL_BASE_URL': PROXY,
                  'KIMI_MODEL_API_KEY': 'local'},
    'cline': {'CLINE_PROVIDER': 'openai-compatible', 'CLINE_BASE_URL': PROXY,
              'CLINE_API_KEY': 'local', 'CLINE_MODEL': 'ocg/longcat-2.5-preview-free'},
    'grok': {'GROK_DEFAULT_MODEL': 'ocg/longcat-2.5-preview-free',
             'GROK_XAI_API_BASE_URL': PROXY, 'OPENAI_MODEL': 'ocg/longcat-2.5-preview-free',
             'XAI_API_KEY': 'local'},
}
for at, env in ENVS.items():
    print(f'  {at}:', rpc('acp_update_agent_env', {'agentType': at, 'enabled': True, 'env': env}))

print()
print('完成。')
