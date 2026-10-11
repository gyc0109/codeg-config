#!/bin/bash
# Mac：用本机 CC key 重新探测套餐可用性（与服务器同口径）
CC=$(cat "$HOME/.codeg/commandcode-goat-key")
OUT=/tmp/cc_reprobe.txt
: > "$OUT"

probe() {
  m="$1"
  r=$(curl -sS --max-time 45 https://api.commandcode.ai/provider/v1/chat/completions \
      -H "Authorization: Bearer $CC" -H 'Content-Type: application/json' \
      -d "{\"model\":\"$m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":64}" 2>/dev/null)
  if echo "$r" | grep -q '"choices"'; then echo "OK $m" >> "$OUT"
  elif echo "$r" | grep -q 'MODEL_NOT_IN_PLAN'; then echo "DENIED $m" >> "$OUT"
  elif echo "$r" | grep -q 'must be called via'; then echo "MSGONLY $m" >> "$OUT"
  elif echo "$r" | grep -qi 'Authentication failed'; then echo "AUTHFAIL $m" >> "$OUT"
  elif echo "$r" | grep -qi 'Model not exist'; then echo "NOTEXIST $m" >> "$OUT"
  else echo "ERR $m $(echo "$r" | head -c 70)" >> "$OUT"; fi
}
export -f probe
export CC OUT

python3 -c "
import json,sys
d=json.load(open('/tmp/cc_models.json'))
print('\n'.join(m['id'] for m in (d.get('data') or [])))
" > /tmp/cc_ids.txt

cat /tmp/cc_ids.txt | xargs -P 6 -I{} bash -c 'probe "{}"'

echo "共 $(wc -l < /tmp/cc_ids.txt | tr -d ' ') 个"
for k in OK DENIED MSGONLY AUTHFAIL NOTEXIST ERR; do
  printf '  %-10s %s\n' "$k" "$(grep -c "^$k" $OUT)"
done
echo
echo "  ── 非 OK 的 ──"
grep -vE '^OK' $OUT | sed 's/^/    /'
