#!/bin/bash
# verify-migration.sh — 迁移一致性硬核对
#   1) 文件级：rsync 干跑逐项比对，必须零输出
#   2) 数据库级：两边各做一致快照，逐表行数 + 全库 dump 哈希
#   3) 会话级：conversation 逐条比对 + 各 agent 记录文件数/字节数
set -u
TARGET=root@150.109.241.115
OUT=/root/codeg-work/verify-migration-report.txt
: > "$OUT"
say(){ echo "$*" | tee -a "$OUT"; }
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=15)

say "================ 迁移一致性核对 $(date '+%F %T') ================"

# ---------- 1. 文件级 ----------
say ""
say "【1】文件级比对（rsync 干跑，应当没有任何输出）"
CHK_DIRS=(/root /usr/local/bin /usr/local/sbin /usr/local/share/codeg /usr/local/share/codeg-opencode-quota
          /usr/local/go /opt/litellm /opt/litellm-venv /etc/nginx /etc/letsencrypt /var/www /usr/lib/node_modules)
total_diff=0
for d in "${CHK_DIRS[@]}"; do
  [ -e "$d" ] || continue
  n=$(rsync -aHAX --numeric-ids -n --itemize-changes --delete \
        -e "ssh -o BatchMode=yes -o ConnectTimeout=15" \
        --exclude='.rustup/' --exclude='.cache/' --exclude='.npm/_cacache/' \
        --exclude='.ssh/authorized_keys' --exclude='**/*.sock' --exclude='.Xauthority' \
        "$d/" "$TARGET:$d/" 2>/dev/null | grep -c '^[<>ch.*]' )
  printf "  %-45s 差异 %s 项\n" "$d" "$n" | tee -a "$OUT"
  total_diff=$((total_diff + n))
done
say "  ---- 文件差异合计: $total_diff"

# ---------- 2. 数据库级 ----------
say ""
say "【2】codeg.db 一致快照比对"
DB=/root/.local/share/codeg/codeg.db
SNAP_S=/root/codeg-work/verify/src-snapshot.db
SNAP_T=/root/codeg-work/verify/dst-snapshot.db
rm -f "$SNAP_S" "$SNAP_T"
sqlite3 "$DB" ".backup '$SNAP_S'"
"${SSH[@]}" "$TARGET" "sqlite3 $DB \".backup '/root/.local/share/codeg/_snap.db'\""
rsync -a -e "ssh -o BatchMode=yes" "$TARGET:/root/.local/share/codeg/_snap.db" "$SNAP_T"
say "  源快照 $(du -h "$SNAP_S" | cut -f1)  目标快照 $(du -h "$SNAP_T" | cut -f1)"

tables=$(sqlite3 "$SNAP_S" "select name from sqlite_master where type='table' and name not like 'sqlite_%' order by name")
dbdiff=0
for t in $tables; do
  a=$(sqlite3 "$SNAP_S" "select count(*) from \"$t\"")
  b=$(sqlite3 "$SNAP_T" "select count(*) from \"$t\"" 2>/dev/null || echo MISSING)
  if [ "$a" != "$b" ]; then
    printf "  !! %-32s 源 %-8s 目标 %s\n" "$t" "$a" "$b" | tee -a "$OUT"
    dbdiff=$((dbdiff+1))
  fi
done
say "  逐表行数: $(echo "$tables" | wc -l) 张表, 不一致 $dbdiff 张"

H1=$(sqlite3 "$SNAP_S" .dump | sha256sum | cut -d' ' -f1)
H2=$(sqlite3 "$SNAP_T" .dump | sha256sum | cut -d' ' -f1)
say "  源 dump  sha256: $H1"
say "  目标dump  sha256: $H2"
[ "$H1" = "$H2" ] && say "  ✅ 全库内容完全一致" || say "  ❌ 全库 dump 不一致（行内数据有差异）"

# ---------- 3. 会话级 ----------
say ""
say "【3】会话明细"
say "  conversation 条数: 源 $(sqlite3 "$SNAP_S" 'select count(*) from conversation') / 目标 $(sqlite3 "$SNAP_T" 'select count(*) from conversation')"
say "  token_usage_turn: 源 $(sqlite3 "$SNAP_S" 'select count(*) from token_usage_turn') / 目标 $(sqlite3 "$SNAP_T" 'select count(*) from token_usage_turn')"
say "  chat_channel_message_log: 源 $(sqlite3 "$SNAP_S" 'select count(*) from chat_channel_message_log') / 目标 $(sqlite3 "$SNAP_T" 'select count(*) from chat_channel_message_log')"

SESS_LIST=".claude/projects .codex/sessions .pi .kimi-code .grok .gemini .qoder .kiro .cline .hermes .openclaw .codebuddy .zcode .cursor .local/share/codeg/chat-sessions .local/share/codeg/uploads"
say "  各 agent 会话记录文件（数量 / 字节）:"
for p in $SESS_LIST; do
  a=$(find "/root/$p" -type f 2>/dev/null | wc -l); as=$(find "/root/$p" -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1}END{print s+0}')
  b=$("${SSH[@]}" "$TARGET" "find /root/$p -type f 2>/dev/null | wc -l; find /root/$p -type f -printf '%s\n' 2>/dev/null | awk '{s+=\$1}END{print s+0}'" | tr '\n' ' ')
  bs=$(echo "$b" | awk '{print $2+0}')
  mark="OK"; [ "$a" != "${b%% *}" ] && mark="!!"
  [ "$as" != "$bs" ] && mark="!!"
  printf "    %-3s %-40s %5s 个 %12s B | 目标 %5s 个 %12s B\n" "$mark" "$p" "$a" "$as" "${b%% *}" "$bs" | tee -a "$OUT"
done

say ""
say "================ 核对结束 ================"
