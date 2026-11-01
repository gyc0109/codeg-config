#!/bin/bash
set -u
TARGET=root@150.109.241.115
SSHOPT="ssh -o BatchMode=yes -o ConnectTimeout=15"
LOG=/root/codeg-work/sync-missing.log
: > "$LOG"
say(){ echo "[$(date +%T)] $*" | tee -a "$LOG"; }

say "=== 补迁遗漏项 ==="
push(){ local d="$1"
  [ -e "$d" ] || { say "跳过 $d"; return 0; }
  local dst="${d%/}"
  case "$dst" in ""|"/"|"//") say "!!! 拒绝根目录"; return 1;; esac
  say "--> $dst"
  rsync -aHAX --numeric-ids -z --partial --delete --itemize-changes \
    -e "$SSHOPT" "$d/" "$TARGET:$dst/" >>"$LOG" 2>&1
  local rc=$?; [ $rc -eq 0 ] && say "    ok" || say "    !!! rc=$rc"
  return 0; }

# 关键配置
for f in /etc/profile.d/dev-env.sh \
         /etc/systemd/system/codeg.service.d/10-web-timeout-patch.conf \
         /etc/systemd/system/codeg.service.d/20-pi-acp-provider-label.conf; do
  [ -f "$f" ] || { say "跳过 $f"; continue; }
  rsync -a -e "$SSHOPT" "$f" "$TARGET:$f" >>"$LOG" 2>&1 && say "  ok  $f" || say "  !!! $f"
done

# 大件
push /opt/gradle/
push /usr/local/share/fonts/
push /usr/local/share/lua/
push /usr/local/share/.cache/
push /usr/local/lib/

say "=== 补迁结束 ==="
