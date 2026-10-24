#!/bin/bash
# 在目标机上把 migrate-export.sh 打的 bundle 还原成和源机一致的 codeg 环境。
#
#   ./migrate-import.sh <bundle目录> [选项]
#
#   --skip-packages   不装基础包（目标机已具备 node/nginx/sqlite3/curl）
#   --skip-services   只铺文件，不 systemctl enable/start
#
# 需要 root。目标机建议 Debian 13 x86_64，与源机同架构。
set -euo pipefail

BUNDLE="${1:?用法: $0 <bundle目录> [--skip-packages] [--skip-services]}"
BUNDLE="$(cd "$BUNDLE" && pwd)"
shift || true
SKIP_PKGS=0
SKIP_SVC=0
for a in "$@"; do
  case "$a" in
    --skip-packages) SKIP_PKGS=1 ;;
    --skip-services) SKIP_SVC=1 ;;
    *) echo "未知参数: $a" >&2; exit 2 ;;
  esac
done

ROOTFS="$BUNDLE/rootfs"
META="$BUNDLE/meta"
[ -d "$ROOTFS" ] || { echo "bundle 里没有 rootfs：$BUNDLE" >&2; exit 1; }

log(){ printf '[%s] %s\n' "$(date +%T)" "$*"; }
[ "$(id -u)" = 0 ] || { echo "请用 root 运行" >&2; exit 1; }

# ---------------------------------------------------------------- 预检
log "预检"
[ -f "$META/system.txt" ] && sed 's/^/    源机 /' "$META/system.txt"
SRC_ARCH="$(awk -F': ' '/^arch:/{print $2}' "$META/system.txt" 2>/dev/null || true)"
if [ -n "$SRC_ARCH" ] && [ "$SRC_ARCH" != "$(uname -m)" ]; then
  echo "!! 架构不一致：源 $SRC_ARCH / 目标 $(uname -m)" >&2
  echo "   binary agent（antigravity / cursor / opencode）和 node 不能直接拷。" >&2
  exit 1
fi

# ---------------------------------------------------------------- 1. 基础包
if [ "$SKIP_PKGS" = 0 ]; then
  log "安装基础包"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends \
    curl ca-certificates rsync sqlite3 nginx python3 python3-venv xz-utils \
    build-essential procps >/dev/null
else
  log "--skip-packages：跳过基础包"
fi

# node：源机是 dpkg 装的 nodejs，bundle 里带了 /usr/bin/node
if ! command -v node >/dev/null || [ "$(node -v 2>/dev/null | sed 's/^v//')" \< "22" ]; then
  if [ -x "$ROOTFS/usr/bin/node" ]; then
    log "恢复 /usr/bin/node（从 bundle）"
    install -Dm755 "$ROOTFS/usr/bin/node" /usr/bin/node
  else
    log "bundle 里没有 node，尝试 NodeSource 装 24.x"
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - >/dev/null
    apt-get install -y -qq nodejs >/dev/null
  fi
fi
log "node $(node -v 2>/dev/null) / npm $(npm -v 2>/dev/null)"

# ---------------------------------------------------------------- 2. 备份目标机现状
if [ -f /root/.local/share/codeg/codeg.db ]; then
  BK="/root/codeg-import-backup-$(date +%Y%m%d-%H%M%S)"
  log "目标机已有 codeg 数据，先备份到 $BK"
  mkdir -p "$BK"
  cp -a /root/.local/share/codeg/codeg.db "$BK"/ 2>/dev/null || true
  [ -f /etc/codeg.env ] && cp -a /etc/codeg.env "$BK"/ 2>/dev/null || true
fi

# ---------------------------------------------------------------- 3. 停服务
if [ "$SKIP_SVC" = 0 ]; then
  log "停 codeg（避免写 DB 冲突）"
  systemctl stop codeg.service 2>/dev/null || true
fi

# ---------------------------------------------------------------- 4. 铺文件
log "还原文件（rootfs -> /）"
rsync -aHAX --numeric-ids "$ROOTFS"/ /
# 一致快照覆盖活库，并清掉旧的 wal/shm（否则会回放成旧状态）
if [ -f "$META/sqlite/codeg.db" ]; then
  log "还原 codeg.db 一致快照"
  install -d /root/.local/share/codeg
  rm -f /root/.local/share/codeg/codeg.db-wal /root/.local/share/codeg/codeg.db-shm
  install -m 600 "$META/sqlite/codeg.db" /root/.local/share/codeg/codeg.db
fi

# ---------------------------------------------------------------- 5. 重建 /usr/bin 软链
if [ -f "$META/symlinks.txt" ]; then
  log "重建 /usr/bin 下的 agent 软链"
  n=0
  while IFS=$'\t' read -r name target; do
    [ -n "$name" ] || continue
    [ -e "/usr/bin/$target" ] || [ -e "/usr/lib/node_modules/${target#../lib/node_modules/}" ] || continue
    ln -sfn "$target" "/usr/bin/$name"
    n=$((n+1))
  done < "$META/symlinks.txt"
  log "  重建 $n 条"
fi

# ---------------------------------------------------------------- 6. 服务
if [ "$SKIP_SVC" = 0 ]; then
  log "重载 systemd"
  # venv 绑死源机的 /usr/bin/python3.13。目标机 python 版本不同就重建
  # （requirements 清单在 bundle 里由 export 一并收走）
  REQ="$ROOTFS/root/migrate-requirements-litellm.txt"
  if ! /opt/litellm-venv/bin/python -V >/dev/null 2>&1; then
    if [ -f "$REQ" ]; then
      log "  venv 不可用，用 $REQ 重建"
      rm -rf /opt/litellm-venv
      /usr/bin/python3 -m venv /opt/litellm-venv
      /opt/litellm-venv/bin/pip install -q --upgrade pip
      /opt/litellm-venv/bin/pip install -q -r "$REQ" && log "  venv 重建完成" || log "  ⚠ venv 重建失败"
    else
      log "  ⚠ venv 不可用且 bundle 里没有 requirements 清单"
    fi
  fi
  systemctl daemon-reload

  # 顺序有依赖：litellm Requires opencode-go-proxy
  for u in opencode-go-proxy litellm commandcode-proxy codeg codeg-port-lockdown; do
    if [ -f "/etc/systemd/system/$u.service" ]; then
      systemctl enable "$u.service" >/dev/null 2>&1 || true
      systemctl restart "$u.service" && log "  $u 已启动" || log "  ⚠ $u 启动失败"
    fi
  done

  if [ -f /etc/nginx/sites-enabled/codeg ]; then
    nginx -t >/dev/null 2>&1 && systemctl restart nginx && log "  nginx 已重启" \
      || log "  ⚠ nginx 配置有问题，先看 nginx -t"
  fi

  # openclaw 的 user 单元（源机是 user scope）
  if [ -f /root/.config/systemd/user/openclaw-gateway.service ]; then
    log "openclaw 是 user 单元，需要你手动: systemctl --user restart openclaw-gateway"
  fi
fi

# ---------------------------------------------------------------- 7. 验证
log "验证"
sleep 3
if [ -f /etc/codeg.env ]; then
  TOKEN=$(grep '^CODEG_TOKEN=' /etc/codeg.env | cut -d= -f2)
  PORT=$(grep '^CODEG_PORT=' /etc/codeg.env | cut -d= -f2); PORT=${PORT:-3080}
  echo "  --- 服务状态 ---"
  for u in opencode-go-proxy litellm commandcode-proxy codeg; do
    printf '  %-20s %s\n' "$u" "$(systemctl is-active "$u" 2>/dev/null)"
  done
  echo "  --- 端口 ---"
  ss -lntp 2>/dev/null | grep -E ':(3080|4000|8897|8898|8899)\b' || echo "  （无监听）"
  echo "  --- codeg API ---"
  curl -sS --max-time 10 -X POST "http://127.0.0.1:$PORT/api/acp_list_agents" \
    -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" -d '{}' \
    | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  agents:",len(d),"available:",sum(1 for a in d if a.get("available")))' 2>/dev/null \
    || echo "  ⚠ API 未通"
  echo "  --- 数据对比 ---"
  if [ -f "$META/sqlite/rowcounts.txt" ]; then
    for t in conversation model_provider agent_setting automation; do
      want=$(awk -v k="$t" '$1==k{print $2}' "$META/sqlite/rowcounts.txt")
      got=$(sqlite3 /root/.local/share/codeg/codeg.db "SELECT count(*) FROM $t;" 2>/dev/null)
      printf '  %-20s 源 %-6s 目标 %s\n' "$t" "${want:-?}" "${got:-?}"
    done
  fi
fi

cat <<'EOF'

完成。还需要人工确认：
  1. 域名/证书：/etc/nginx/sites-available/codeg 里写的是 gycai.top，
     换域名要改 server_name 并重签证书。
  2. openclaw 是 systemd --user 单元，需要登录会话里手动起。
  3. 首次访问 codeg 用 /etc/codeg.env 里的 CODEG_TOKEN。
EOF
