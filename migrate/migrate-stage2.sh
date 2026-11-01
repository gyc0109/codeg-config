#!/bin/bash
# migrate-stage2.sh — 迁移第二批：/etc 自定义项、/usr/local、/opt、/var/www、docker、node_modules
# 只搬「非 apt 包管理」的东西；系统包已经在目标机上用 apt 补齐（726 个）
set -u
TARGET=root@150.109.241.115
LOG=/root/codeg-work/migrate-stage2.log
: > "$LOG"
say(){ echo "[$(date +%T)] $*" | tee -a "$LOG"; }
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=15)
RS=(rsync -aHAX --numeric-ids -z --partial --info=progress2 -e "ssh -o BatchMode=yes -o ConnectTimeout=15")

# push <源路径>  —— 保持绝对路径不变
push(){
  local src="$1" parent rc
  [ -e "$src" ] || { say "跳过(不存在) $src"; return 0; }
  parent="$(dirname "$src")"
  "${SSH[@]}" "$TARGET" "mkdir -p '$parent'" || return 1
  say "--> $src"
  "${RS[@]}" "$src" "$TARGET:$parent/" >> "$LOG" 2>&1
  rc=$?
  [ $rc -ne 0 ] && say "!!! $src 失败 rc=$rc"
  return $rc
}

say "=== stage2 开始 ==="

# ---- 1. 密钥/环境文件 ----
for f in /etc/codeg.env /etc/commandcode-proxy.env /etc/opencode-go-proxy.env \
         /etc/deepseek-official-key /etc/volcengine-ark-key; do
  push "$f"
done

# ---- 2. systemd 单元 ----
for f in codeg.service codeg-port-lockdown.service commandcode-proxy.service \
         litellm.service opencode-go-proxy.service \
         codeg-opencode-quota.service codeg-opencode-quota-api.service; do
  push "/etc/systemd/system/$f"
done
push /etc/systemd/system/codeg.service.d

# ---- 3. nginx / 证书 ----
push /etc/nginx
push /etc/letsencrypt

# ---- 4. 其它 /etc ----
push /etc/profile.d/dev-env.sh
push /etc/apt/sources.list.d/nodesource.list
push /usr/share/keyrings/nodesource.gpg
push /etc/crontab
push /etc/logrotate.d/nginx

# ---- 5. /usr/local（codeg 服务端二进制、脚本、go 工具链、字体）----
push /usr/local/bin
push /usr/local/sbin
push /usr/local/share/codeg
push /usr/local/share/codeg-opencode-quota
push /usr/local/go

# ---- 6. /opt ----
push /opt/litellm
push /opt/litellm-venv
push /opt/nvim-linux-x86_64

# ---- 7. 站点文件 / docker ----
push /var/www
push /var/lib/docker

# ---- 8. node 全局包（所有 codeg agent）----
say "--> /usr/lib/node_modules (约 4.5G)"
"${RS[@]}" --exclude='.package-lock.json.tmp' \
  /usr/lib/node_modules "$TARGET:/usr/lib/" >> "$LOG" 2>&1
say "node_modules rc=$?"

say "=== stage2 ALL DONE ==="
