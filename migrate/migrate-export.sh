#!/bin/bash
# 在源机上打一个迁移 bundle，目标机用 migrate-import.sh 还原。
#
#   ./migrate-export.sh [输出目录] [选项]
#
#   --slim             跳过 /usr/lib/node_modules、acp-binaries、日志（体积约 1/3）
#   --no-letsencrypt   跳过 /etc/letsencrypt（换域名或换机器重新签时用）
#
# 默认是全量：目标是「一摸一样」。bundle 里含明文密钥，注意保管。
set -euo pipefail

OUT="${1:-/root/migrate-out/codeg-$(date +%Y%m%d-%H%M%S)}"
shift || true
SLIM=0
WITH_LE=1
for a in "$@"; do
  case "$a" in
    --slim) SLIM=1 ;;
    --no-letsencrypt) WITH_LE=0 ;;
    *) echo "未知参数: $a" >&2; exit 2 ;;
  esac
done

BUNDLE="$OUT/bundle"
ROOTFS="$BUNDLE/rootfs"
META="$BUNDLE/meta"
mkdir -p "$ROOTFS" "$META"/{systemd,sqlite}

log(){ printf '[%s] %s\n' "$(date +%T)" "$*"; }

# ---------------------------------------------------------------- 一致性
# codeg.db 有 WAL，直接拷会拿到半写状态。用 sqlite .backup 取一致快照。
DB=/root/.local/share/codeg/codeg.db
if [ -f "$DB" ]; then
  log "快照 codeg.db"
  sqlite3 "$DB" ".backup '$META/sqlite/codeg.db'"
  # 顺带把 schema 和行数记下来，导入后可对比
  sqlite3 "$META/sqlite/codeg.db" ".tables" > "$META/sqlite/tables.txt"
  for t in conversation folder model_provider agent_setting automation automation_run token_usage_turn; do
    printf '%-20s %s\n' "$t" "$(sqlite3 "$META/sqlite/codeg.db" "SELECT count(*) FROM $t;" 2>/dev/null || echo '?')"
  done > "$META/sqlite/rowcounts.txt"
fi

# ---------------------------------------------------------------- 通用暂存
EXCLUDES=(
  --exclude='*.sock' --exclude='*.lock' --exclude='**/node_modules/.cache'
  --exclude='.npm/_cacache' --exclude='**/.cache/**'
)
stage(){
  local src="$1"; shift
  [ -e "$src" ] || { log "跳过（不存在）$src"; return 0; }
  local dst="$ROOTFS${src}"
  mkdir -p "$(dirname "$dst")"
  log "收 $src"
  rsync -aHAX --numeric-ids "${EXCLUDES[@]}" "$@" "$src" "$(dirname "$dst")/" \
    || echo "  ⚠ 部分文件未拷（见上）" >&2
}

# ---------------------------------------------------------------- 1. codeg 本体
stage /usr/local/bin
stage /usr/local/share/codeg
stage /etc/codeg.env
stage /etc/systemd/system/codeg.service
stage /etc/systemd/system/codeg-port-lockdown.service
# node 本身（源机是 dpkg 的 nodejs 包），目标机没有就靠它
stage /usr/bin/node

# ---------------------------------------------------------------- 2. 模型路由
stage /usr/local/bin/opencode-go-proxy
stage /usr/local/bin/commandcode-proxy
stage /etc/opencode-go-proxy.env
stage /etc/commandcode-proxy.env
stage /etc/systemd/system/opencode-go-proxy.service
stage /etc/systemd/system/litellm.service
stage /etc/systemd/system/commandcode-proxy.service
stage /opt/litellm
stage /opt/litellm-venv

# ---------------------------------------------------------------- 3. codeg 数据
# 活的 db/-wal/-shm 不拷，用上面的一致快照代替
DATA_EXCL=(
  --exclude='codeg.db' --exclude='codeg.db-wal' --exclude='codeg.db-shm'
  --exclude='*.lock'
)
[ "$SLIM" = 1 ] && DATA_EXCL+=(--exclude='acp-binaries')
stage /root/.local/share/codeg "${DATA_EXCL[@]}"
stage /root/.local/bin
stage /root/.local/state

# ---------------------------------------------------------------- 4. agent 配置与历史
for d in .claude .codex .gemini .qoder .kiro .kimi-code .cline .hermes \
         .openclaw .grok .pi .codebuddy .zcode .cursor .codeg .config; do
  stage "/root/$d"
done

# ---------------------------------------------------------------- 5. 工作区与仓库
stage /root/Labs
stage /root/.zshrc
stage /root/.bashrc
stage /root/.profile

# ---------------------------------------------------------------- 6. nginx
stage /etc/nginx/nginx.conf
stage /etc/nginx/sites-available/codeg
stage /etc/nginx/sites-enabled/codeg
stage /etc/nginx/snippets
stage /etc/nginx/.htpasswd
[ "$WITH_LE" = 1 ] && stage /etc/letsencrypt

# ---------------------------------------------------------------- 7. 可选大件
if [ "$SLIM" = 0 ]; then
  # acp-binaries 已在上一节随 codeg 数据一起收了
  stage /usr/lib/node_modules
else
  log "--slim：跳过 /usr/lib/node_modules 与 acp-binaries"
fi

# ---------------------------------------------------------------- 元信息
log "记录系统信息"
{
  echo "date: $(date -Is)"
  echo "host: $(hostname)"
  echo "os: $(. /etc/os-release; echo "$PRETTY_NAME")"
  echo "kernel: $(uname -r)"
  echo "arch: $(uname -m)"
  echo "node: $(node -v 2>/dev/null)"
  echo "npm: $(npm -v 2>/dev/null)"
  echo "python3: $(python3 -V 2>&1)"
} > "$META/system.txt"

# dpkg 清单：目标机装基础包时对照用
dpkg --get-selections > "$META/dpkg-selections.txt" 2>/dev/null || true

# npm 全局包精确版本
for p in /usr/lib/node_modules/*/package.json /usr/lib/node_modules/@*/*/package.json; do
  [ -f "$p" ] || continue
  node -e "const p=require('$p');console.log(p.name+'@'+p.version)" 2>/dev/null
done | sort -u > "$META/npm-globals.txt" 2>/dev/null || true

# /usr/bin 下的 node_modules 软链图，导入时据此重建
find /usr/bin -maxdepth 1 -type l -lname '../lib/node_modules*' -printf '%f\t%l\n' \
  | sort > "$META/symlinks.txt" 2>/dev/null || true

# systemd 单元原文（FragmentPath 可能不在 /etc/systemd/system）
for u in codeg codeg-port-lockdown litellm commandcode-proxy opencode-go-proxy nginx; do
  systemctl cat "$u.service" 2>/dev/null > "$META/systemd/$u.service.txt" || true
done

# openclaw 的 user 单元
if [ -d /root/.config/systemd/user ]; then
  mkdir -p "$META/systemd/user"
  cp -a /root/.config/systemd/user/. "$META/systemd/user/" 2>/dev/null || true
fi

# venv 的 python 版本清单：目标机 python 版本不同时用它重建 /opt/litellm-venv
mkdir -p "$ROOTFS/root"
cp "$(dirname "$0")/requirements-litellm.txt" "$ROOTFS/root/migrate-requirements-litellm.txt" 2>/dev/null \
  || log "⚠ 缺少 requirements-litellm.txt，目标机 python 版本不同时 venv 无法重建"

# ---------------------------------------------------------------- 清单
log "生成 MANIFEST"
{
  echo "codeg 迁移 bundle"
  echo "生成时间: $(date -Is)"
  echo "源机: $(hostname)  $(uname -m)"
  echo "模式: $([ "$SLIM" = 1 ] && echo slim || echo full)"
  echo
  echo "== meta =="
  ( cd "$META" && find . -type f -printf '%10s  %p\n' | sort -k2 )
  echo
  echo "== rootfs 顶层 =="
  du -sh "$ROOTFS"/* 2>/dev/null
  echo
  echo "== 行数 =="
  cat "$META/sqlite/rowcounts.txt" 2>/dev/null
} > "$BUNDLE/MANIFEST.txt"

log "总体积"
du -sh "$OUT"
echo
echo "bundle 就绪: $OUT"
echo "打包传输： tar -C '$OUT' -czf /root/codeg-migrate-$(date +%Y%m%d).tar.gz bundle"
echo "⚠ 内含明文密钥（/etc/*.env、agent 授权文件），传输与存放注意权限。"
