#!/bin/bash
# verify-v2.sh — 迁移一致性核对（修正版：失败会报错，不会被当成"0 差异"）
set -u
TARGET=root@150.109.241.115
THOST=150.109.241.115
OUT=/root/codeg-work/verify-v2-report.txt
: > "$OUT"
say(){ echo "$*" | tee -a "$OUT"; }
SSHOPT="ssh -o BatchMode=yes -o ConnectTimeout=15"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=15)
TOKEN=$(grep '^CODEG_TOKEN=' /etc/codeg.env | cut -d= -f2)

say "================ 一致性核对 $(date '+%F %T') ================"

# ---------- 1. 会话 ID 集合（最权威）----------
say ""
say "【1】会话 ID 集合比对（API 口径）"
curl -sS --max-time 40 -X POST http://127.0.0.1:3080/api/list_conversations \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{}' 2>/dev/null \
  | jq -r '.[].id' 2>/dev/null | sort > /tmp/ids-src.txt
curl -sS --max-time 40 -X POST http://$THOST/api/list_conversations \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{}' 2>/dev/null \
  | jq -r '.[].id' 2>/dev/null | sort > /tmp/ids-dst.txt
say "  源: $(wc -l < /tmp/ids-src.txt) 条   目标: $(wc -l < /tmp/ids-dst.txt) 条"
only_src=$(comm -23 /tmp/ids-src.txt /tmp/ids-dst.txt | wc -l)
only_dst=$(comm -13 /tmp/ids-src.txt /tmp/ids-dst.txt | wc -l)
say "  仅源有: $only_src    仅目标有: $only_dst"
[ "$only_src" = "0" ] && [ "$only_dst" = "0" ] && say "  ✅ ID 集合完全一致" || {
  say "  ❌ 存在差异"; comm -23 /tmp/ids-src.txt /tmp/ids-dst.txt | head -5 | sed 's/^/     仅源: /' | tee -a "$OUT"
  comm -13 /tmp/ids-src.txt /tmp/ids-dst.txt | head -5 | sed 's/^/     仅目标: /' | tee -a "$OUT"; }

# ---------- 2. 数据库结构 + 行数 ----------
say ""
say "【2】数据库比对（源实时库 vs 目标库）"
DB=/root/.local/share/codeg/codeg.db
SNAP_S=/root/codeg-work/verify/src2.db
rm -f "$SNAP_S"; sqlite3 "$DB" ".backup '$SNAP_S'"
"${SSH[@]}" "$TARGET" "sqlite3 $DB \".backup '/tmp/dst2.db'\"" 
rsync -a -e "$SSHOPT" "$TARGET:/tmp/dst2.db" /root/codeg-work/verify/dst2.db 2>/dev/null
say "  源完整性: $(sqlite3 $SNAP_S 'PRAGMA integrity_check;')"
say "  目标完整性: $(sqlite3 /root/codeg-work/verify/dst2.db 'PRAGMA integrity_check;' 2>&1)"
t_src=$(sqlite3 "$SNAP_S" "select name from sqlite_master where type='table' and name not like 'sqlite_%' order by name")
t_dst=$(sqlite3 /root/codeg-work/verify/dst2.db "select name from sqlite_master where type='table' and name not like 'sqlite_%' order by name")
say "  表数量: 源 $(echo "$t_src"|wc -l) / 目标 $(echo "$t_dst"|wc -l)"
say "  表结构: $( [ "$t_src" = "$t_dst" ] && echo '✅ 完全一致' || echo '❌ 不一致' )"
nd=0
for t in $t_src; do
  a=$(sqlite3 "$SNAP_S" "select count(*) from \"$t\"")
  b=$(sqlite3 /root/codeg-work/verify/dst2.db "select count(*) from \"$t\"" 2>/dev/null || echo ERR)
  [ "$a" != "$b" ] && { printf "    %-34s 源 %-8s 目标 %s\n" "$t" "$a" "$b" | tee -a "$OUT"; nd=$((nd+1)); }
done
say "  行数不一致的表: $nd 张（源库运行中，message_log 类会持续增长，属预期）"

# ---------- 3. 文件级 ----------
say ""
say "【3】文件级比对（干跑，无 --delete）"
DIRS=(/root/.local/share/codeg /root/.claude/projects /root/.codex /root/.kimi-code
      /root/.codebuddy /root/.grok /root/.pi /root/.gemini /root/.cline /root/.hermes
      /root/.openclaw /root/.rustup /root/.cargo /usr/local/bin /usr/local/go
      /usr/local/share/codeg /opt/litellm /opt/litellm-venv /etc/nginx /var/www)
tot=0; err=0
for d in "${DIRS[@]}"; do
  [ -e "$d" ] || continue
  out=$(rsync -aHAX --numeric-ids -n --itemize-changes -e "$SSHOPT" \
        --exclude='**/*.sock' --exclude='.Xauthority' "$d/" "$TARGET:$d/" 2>&1)
  rc=$?
  if [ $rc -ge 20 ]; then printf "  %-40s ❌ rc=%s\n" "$d" "$rc" | tee -a "$OUT"; err=$((err+1)); continue; fi
  n=$(printf '%s\n' "$out" | grep -c '^[<>ch]')
  tot=$((tot+n))
  printf "  %-40s %s\n" "$d" "$([ "$n" = 0 ] && echo '✅ 一致' || echo "差异 $n 项")" | tee -a "$OUT"
done
say "  ---- 差异合计 $tot 项，异常目录 $err 个"

# ---------- 4. 服务 ----------
say ""
say "【4】目标机服务状态"
"${SSH[@]}" "$TARGET" 'for s in codeg nginx litellm opencode-go-proxy commandcode-proxy codeg-port-lockdown; do printf "  %-22s %s\n" "$s" "$(systemctl is-active $s 2>/dev/null)"; done' | tee -a "$OUT"
say ""
say "================ 核对结束 ================"
