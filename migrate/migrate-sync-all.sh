#!/bin/bash
# sync-all.sh — 第 4 步：数据同步（目标路径 == 源路径，绝不推算）
set -u
TARGET=root@150.109.241.115
LOG=/root/codeg-work/sync-all.log
: > "$LOG"
say(){ echo "[$(date +%T)] $*" | tee -a "$LOG"; }
SSHOPT="ssh -o BatchMode=yes -o ConnectTimeout=15"

say "===== 数据同步开始 ====="

push(){ local src="$1"; shift
  [ -e "$src" ] || { say "跳过 $src (不存在)"; return 0; }
  local dst="${src%/}"
  case "$dst" in ""|"/"|"//") say "!!! 拒绝：目标解析为根目录 ($src)"; return 1;; esac
  say "--> $src  =>  $TARGET:$dst/"
  rsync -aHAX --numeric-ids -z --partial --delete --itemize-changes \
    -e "$SSHOPT" "$@" "$src" "$TARGET:$dst/" >>"$LOG" 2>&1
  local rc=$?
  if [ $rc -eq 0 ] || [ $rc -eq 24 ]; then say "    ok (rc=$rc)"
  else say "    !!! rc=$rc"; fi
  return 0; }

# 1) 配置与服务定义（小件先走，让服务能立起来）
say "--- 1/4 配置文件 ---"
for f in /etc/codeg.env /etc/opencode-go-proxy.env /etc/commandcode-proxy.env \
         /etc/deepseek-official-key /etc/volcengine-ark-key \
         /etc/systemd/system/codeg.service /etc/systemd/system/codeg-opencode-quota.service \
         /etc/systemd/system/codeg-opencode-quota-api.service /etc/systemd/system/codeg-port-lockdown.service \
         /etc/systemd/system/opencode-go-proxy.service /etc/systemd/system/commandcode-proxy.service \
         /etc/systemd/system/litellm.service; do
  [ -f "$f" ] || { say "跳过 $f"; continue; }
  rsync -a -e "$SSHOPT" "$f" "$TARGET:$f" >>"$LOG" 2>&1 && say "  ok  $f" || say "  !!! $f"
done

# 2) 程序与共享数据
say "--- 2/4 程序 ---"
push /usr/local/bin/   --exclude=tat_agent
push /usr/local/sbin/
push /usr/local/go/
push /usr/local/share/codeg/
push /usr/local/share/codeg-opencode-quota/
push /opt/litellm/
push /opt/litellm-venv/
push /opt/nvim-linux-x86_64/
push /var/www/
push /var/lib/docker/
push /etc/nginx/
push /etc/letsencrypt/

# 3) 依赖树（最大件）
say "--- 3/4 node_modules (4.5G，最慢) ---"
push /usr/lib/node_modules/

# 4) 家目录
say "--- 4/4 /root (4.9G) ---"
push /root/ --exclude='.ssh/authorized_keys' --exclude='**/*.sock' --exclude='.Xauthority'

say "===== 数据同步结束 ====="
