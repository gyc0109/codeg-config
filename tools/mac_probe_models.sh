#!/bin/bash
# 在 Mac 上盘点各供应商可见的模型
OCG=$(cat "$HOME/.codeg/opencode-go-key")
CC=$(cat "$HOME/.codeg/commandcode-goat-key")
echo "═══ OpenCode Go ($(printf %s "$OCG" | head -c 14)...) ═══"
curl -sS --max-time 60 https://opencode.ai/zen/go/v1/models -H "Authorization: Bearer $OCG" -H 'x-opencode-session: probe' 2>/dev/null > /tmp/ocg_models.json
python3 -c "
import json
try:
    d=json.load(open('/tmp/ocg_models.json'))
    ids=sorted(m['id'] for m in (d.get('data') or []))
    print(f'  共 {len(ids)} 个')
    json.dump(ids,open('/tmp/ocg_ids.json','w'))
except Exception as e:
    print('  解析失败:',str(e)[:80]); open('/tmp/ocg_ids.json','w').write('[]')
"
echo
echo "═══ Command Code ($(printf %s "$CC" | head -c 14)...) ═══"
curl -sS --max-time 60 https://api.commandcode.ai/provider/v1/models -H "Authorization: Bearer $CC" 2>/dev/null > /tmp/cc_models.json
python3 -c "
import json
try:
    d=json.load(open('/tmp/cc_models.json'))
    ms=d.get('data') or []
    print(f'  共 {len(ms)} 个')
    ep={m['id']:sorted(m.get('supported_endpoints') or []) for m in ms}
    from collections import Counter
    for k,v in Counter(tuple(x) for x in ep.values()).items():
        print(f'    {list(k)}: {v} 个')
except Exception as e:
    print('  解析失败:',str(e)[:80])
"
