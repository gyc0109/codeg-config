#!/usr/bin/env bash
# ============================================================================
#  在【源机】（东京 38.174.218.71）上执行，不要在新机上跑。
#
#  作用：
#    1. 把源机最后的 codeg.db 快照和会话正文，搬到新机的 /root/final-from-source/
#       —— 注意是**独立目录**，绝不覆盖新机正在用的数据
#    2. 停掉并禁用源机 codeg，避免两个实例同时连微信 bot 重复回复
#
#  为什么不能直接覆盖新机数据：
#    切换之后你这个对话是在新机上继续写的，新机的 jsonl 比源机的新。
#    再从源机 rsync 回去会把新机的内容回退掉。
#    所以先放到 final-from-source/，需要时人工比对合并。
#
#  用法：
#    bash final-sync-from-source.sh            # 只搬数据，不停 codeg
#    bash final-sync-from-source.sh --stop     # 搬完再停掉源机 codeg
# ============================================================================
set -uo pipefail

TARGET=150.109.241.115
DEST=/root/final-from-source
STAMP=$(date +%Y%m%d-%H%M%S)
DB=/root/.local/share/codeg/codeg.db
STOP=0

[ "${1:-}" = "--stop" ] && STOP=1

say(){ echo "[$(date +%H:%M:%S)] $*"; }

say "=== 1. 源机数据库一致性快照（WAL 必须用 .backup） ==="
sqlite3 "$DB" ".backup '/tmp/codeg-source-final-$STAMP.db'"
say "  快照 $(stat -c%s "/tmp/codeg-source-final-$STAMP.db") 字节"
say "  integrity: $(sqlite3 "/tmp/codeg-source-final-$STAMP.db" 'PRAGMA integrity_check;')"

say "=== 2. 在新机上建独立目录 ==="
ssh -o BatchMode=yes "$TARGET" "mkdir -p $DEST"

say "=== 3. 传数据库快照 ==="
rsync -z --partial -e "ssh -o BatchMode=yes" \
  "/tmp/codeg-source-final-$STAMP.db" "$TARGET:$DEST/" \
  && say "  ok" || say "  !!! 失败"

say "=== 4. 传会话正文（放进子目录，不覆盖新机现有文件） ==="
rsync -aHAX --numeric-ids -z --partial -e "ssh -o BatchMode=yes" \
  /root/.claude/projects/ "$TARGET:$DEST/projects/" \
  && say "  ok" || say "  !!! 失败"

say "=== 5. 传 chat-sessions / uploads ==="
rsync -aHAX --numeric-ids -z --partial -e "ssh -o BatchMode=yes" \
  /root/.local/share/codeg/chat-sessions/ "$TARGET:$DEST/chat-sessions/" \
  && say "  chat-sessions ok" || say "  !!! chat-sessions 失败"
rsync -aHAX --numeric-ids -z --partial -e "ssh -o BatchMode=yes" \
  /root/.local/share/codeg/uploads/ "$TARGET:$DEST/uploads/" \
  && say "  uploads ok" || say "  !!! uploads 失败"

say "=== 完成，数据在 $TARGET:$DEST/ ==="

if [ "$STOP" = "1" ]; then
  say "=== 6. 停止并禁用源机 codeg（防止微信 bot 重复回复） ==="
  systemctl disable --now codeg
  say "  状态: $(systemctl is-active codeg 2>/dev/null || echo inactive)"
else
  say ""
  say "源机 codeg 仍在运行：$(systemctl is-active codeg 2>/dev/null)"
  say "确认无误后执行：  systemctl disable --now codeg"
fi
