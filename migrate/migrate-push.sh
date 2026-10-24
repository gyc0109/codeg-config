#!/bin/bash
# 直推到目标机：不落地中转，边传边铺。目标机已有 SSH 访问时用这个。
#
#   ./migrate-push.sh root@1.2.3.4 [选项]
#
#   --slim          跳过 /usr/lib/node_modules 与 acp-binaries（到目标机再 npm 装）
#   --dry-run       只打印要做什么
#   --skip-packages 不装基础包
#
# 前提：目标机已装好 ssh、rsync、curl；能 root 登录。
# 与 migrate-export.sh 的区别：导出模式要 ~9G 本地空间，直推模式不需要。
set -euo pipefail

TARGET="${1:?用法: $0 root@host [--slim] [--dry-run] [--skip-packages]}"
shift || true
SLIM=0; DRY=0; SKIP_PKGS=0
for a in "$@"; do
  case "$a" in
    --slim) SLIM=1 ;;
    --dry-run) DRY=1 ;;
    --skip-packages) SKIP_PKGS=1 ;;
    *) echo "未知参数: $a" >&2; exit 2 ;;
  esac
done

SSH="ssh -o BatchMode=yes -o ConnectTimeout=10 $TARGET"
RSYNC_OPTS=(-aHAX --numeric-ids --info=progress2)
EXCLUDES=(--exclude='*.sock' --exclude='*.lock' --exclude='**/.cache/**' --exclude='.npm/_cacache')

log(){ printf '[%s] %s\n' "$(date +%T)" "$*"; }
run(){ if [ "$DRY" = 1 ]; then echo "  [dry] $*"; else "$@"; fi; }

# ---------------------------------------------------------------- 预检
log "探测目标机"
$SSH 'echo "  host=$(hostname) os=$(. /etc/os-release; echo "$PRETTY_NAME") arch=$(uname -m) free=$(df -h / | awk "NR==2{print \$4}")"'
T_ARCH=$($SSH 'uname -m')
[ "$T_ARCH" = "$(uname -m)" ] || { echo "!! 架构不一致：源 $(uname -m) / 目标 $T_ARCH" >&2; exit 1; }
$SSH 'command -v rsync >/dev/null' || {
  log "目标机没有 rsync，尝试安装"
  run $SSH 'apt-get update -qq && apt-get install -y -qq rsync'
}

# ---------------------------------------------------------------- 基础包
if [ "$SKIP_PKGS" = 0 ]; then
  log "目标机装基础包"
  if [ "$DRY" = 0 ]; then
    $SSH 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq; apt-get install -y -qq --no-install-recommends curl ca-certificates rsync sqlite3 nginx python3 python3-venv xz-utils procps >/dev/null' || echo "  ⚠ 基础包部分失败，继续"
  else
    echo "  [dry] 装 curl rsync sqlite3 nginx python3 ..."
  fi
fi

# ---------------------------------------------------------------- 停目标服务
log "停目标机 codeg（若有）"
run $SSH 'systemctl stop codeg.service 2>/dev/null || true'
run $SSH 'mkdir -p /root/.local/share/codeg'

# ---------------------------------------------------------------- 推 DB 一致快照
SNAP=$(mktemp /tmp/codeg-snapshot.XXXXXX.db)
trap 'rm -f "$SNAP"' EXIT
log "取 codeg.db 一致快照"
sqlite3 /root/.local/share/codeg/codeg.db ".backup '$SNAP'"
run rsync -az "$SNAP" "$TARGET:/root/.local/share/codeg/codeg.db.new"
if [ "$DRY" = 0 ]; then
  $SSH 'cd /root/.local/share/codeg && rm -f codeg.db-wal codeg.db-shm && mv -f codeg.db.new codeg.db && chmod 600 codeg.db'
fi

# ---------------------------------------------------------------- 推目录
# 每个条目：源路径（保持绝对路径结构）
push(){ # push <src> [额外 rsync 参数...]
  local src="$1"; shift
  [ -e "$src" ] || { log "跳过（不存在）$src"; return 0; }
  local parent; parent="$(dirname "$src")"
  log "推 $src"
  run $SSH "mkdir -p '$parent'"
  run rsync "${RSYNC_OPTS[@]}" "${EXCLUDES[@]}" "$@" -e ssh "$src" "$TARGET:$parent/"
}

# codeg 本体
push /usr/local/bin
push /usr/local/share/codeg
push /etc/codeg.env
push /etc/systemd/system/codeg.service
push /etc/systemd/system/codeg-port-lockdown.service
push /usr/bin/node

# 模型路由
push /etc/opencode-go-proxy.env
push /etc/commandcode-proxy.env
push /etc/systemd/system/opencode-go-proxy.service
push /etc/systemd/system/litellm.service
push /etc/systemd/system/commandcode-proxy.service
push /opt/litellm
push /opt/litellm-venv

# codeg 数据（活库已单独推过）
DATA_EXCL=(--exclude='codeg.db' --exclude='codeg.db-wal' --exclude='codeg.db-shm' --exclude='*.lock')
[ "$SLIM" = 1 ] && DATA_EXCL+=(--exclude='acp-binaries')
push /root/.local/share/codeg "${DATA_EXCL[@]}"
push /root/.local/bin
push /root/.local/state

# agent 配置与会话历史
for d in .claude .codex .gemini .qoder .kiro .kimi-code .cline .hermes \
         .openclaw .grok .pi .codebuddy .zcode .cursor .codeg .config; do
  push "/root/$d"
done

# 工作区
push /root/Labs
for f in /root/.zshrc /root/.bashrc /root/.profile; do
  run rsync -aHAX --numeric-ids -e ssh "$f" "$TARGET:$f"
done

# nginx
push /etc/nginx/nginx.conf
push /etc/nginx/sites-available/codeg
push /etc/nginx/snippets
[ -f /etc/nginx/.htpasswd ] && run rsync -aHAX --numeric-ids -e ssh /etc/nginx/.htpasswd "$TARGET:/etc/nginx/"
[ -d /etc/letsencrypt ] && push /etc/letsencrypt

# 可选大件
if [ "$SLIM" = 0 ]; then
  push /usr/lib/node_modules
else
  log "--slim：跳过 /usr/lib/node_modules 与 acp-binaries"
fi

# ---------------------------------------------------------------- 目标机收尾
log "目标机收尾：软链 / systemd / nginx"
SYMLINKS=$(find /usr/bin -maxdepth 1 -type l -lname '../lib/node_modules*' -printf '%f\t%l\n' | sort)
if [ "$DRY" = 1 ]; then
  echo "  [dry] 重建 $(echo "$SYMLINKS" | wc -l) 条软链，reload systemd，起服务"
else
  $SSH 'bash -s' <<REMOTE
set -e
# 软链
while IFS=\$'\t' read -r name target; do
  [ -n "\$name" ] || continue
  [ -e "/usr/bin/\$target" ] || continue
  ln -sfn "\$target" "/usr/bin/\$name"
done <<'SL'
$SYMLINKS
SL

# nginx 站点启用
[ -f /etc/nginx/sites-available/codeg ] && ln -sfn /etc/nginx/sites-available/codeg /etc/nginx/sites-enabled/codeg

chmod 600 /etc/codeg.env /etc/opencode-go-proxy.env /etc/commandcode-proxy.env 2>/dev/null || true
systemctl daemon-reload
$([ "$SKIP_PKGS" = 1 ] && echo "true" || echo "apt-get install -y -qq nginx >/dev/null 2>&1 || true")
for u in opencode-go-proxy litellm commandcode-proxy codeg codeg-port-lockdown; do
  [ -f "/etc/systemd/system/\$u.service" ] || continue
  systemctl enable "\$u.service" >/dev/null 2>&1 || true
  systemctl restart "\$u.service" 2>/dev/null && echo "  \$u ok" || echo "  ⚠ \$u 失败"
done
[ -f /etc/nginx/sites-enabled/codeg ] && { nginx -t >/dev/null 2>&1 && systemctl restart nginx && echo "  nginx ok" || echo "  ⚠ nginx 配置有问题"; }
REMOTE
fi

# ---------------------------------------------------------------- 验证
if [ "$DRY" = 0 ]; then
  log "验证"
  $SSH 'bash -s' <<'REMOTE'
sleep 3
TOKEN=$(grep '^CODEG_TOKEN=' /etc/codeg.env | cut -d= -f2)
PORT=$(grep '^CODEG_PORT=' /etc/codeg.env | cut -d= -f2); PORT=${PORT:-3080}
printf '  node %s | ' "$(node -v 2>/dev/null)"
printf 'npm %s\n' "$(npm -v 2>/dev/null)"
for u in opencode-go-proxy litellm commandcode-proxy codeg; do
  printf '  %-20s %s\n' "$u" "$(systemctl is-active $u 2>/dev/null)"
done
echo "  --- 数据 ---"
sqlite3 /root/.local/share/codeg/codeg.db "SELECT '  conversations',count(*) FROM conversation UNION ALL SELECT '  model_provider',count(*) FROM model_provider UNION ALL SELECT '  agent_setting',count(*) FROM agent_setting UNION ALL SELECT '  automation',count(*) FROM automation;" 2>/dev/null
echo "  --- API ---"
curl -sS --max-time 10 -X POST "http://127.0.0.1:$PORT/api/acp_list_agents" \
  -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" -d '{}' \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  agents:",len(d),"available:",sum(1 for a in d if a.get("available")))' 2>/dev/null \
  || echo "  ⚠ API 未通"
REMOTE
fi

cat <<'EOF'

完成。人工确认项：
  1. 域名/证书：nginx 配置里是 gycai.top，换域名要改 server_name 并重签。
  2. openclaw 是 systemd --user 单元，需登录会话里手动起。
  3. 首次访问 codeg 用目标机 /etc/codeg.env 里的 CODEG_TOKEN。
EOF
