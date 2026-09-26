#!/usr/bin/env bash
# codeg / OpenCode Go 路由配置一键还原
#
#   sudo ./restore.sh              # 还原全部
#   sudo ./restore.sh --dry-run    # 只显示要做什么，不实际写入
#
# 幂等：可重复执行。密钥从 /etc/opencode-go-proxy.env 读取，不会写进 agent 配置。
set -euo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

say()  { printf '  %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
run()  { if (( DRY )); then say "[dry-run] $*"; else "$@"; fi; }

# ---------- 0. 前置检查 ----------
step "0. 前置检查"
KEYFILE=/etc/opencode-go-proxy.env
if [[ ! -f "$KEYFILE" ]]; then
  echo "  ✗ 缺少 $KEYFILE"
  echo "    先执行： sudo cp $PROJ/install/opencode-go-proxy.env.example $KEYFILE"
  echo "             sudo chmod 600 $KEYFILE && sudo vi $KEYFILE   # 填入真实 key"
  exit 1
fi
KEY="$(grep -E '^OPENCODE_GO_API_KEY=' "$KEYFILE" | cut -d= -f2- | tr -d '"\047' || true)"
if [[ -z "$KEY" || "$KEY" == *填入* ]]; then
  echo "  ✗ $KEYFILE 里的 OPENCODE_GO_API_KEY 未填写"
  exit 1
fi
say "密钥已就绪（${KEY:0:6}…${KEY: -4}）"
say "LiteLLM 解释器： $( [[ -x /opt/litellm-venv/bin/litellm ]] && echo 存在 || echo '缺失，需重新安装' )"

# ---------- 1. 代理（:8899）----------
step "1. 部署 opencode-go-proxy（:8899）"
run install -m 0755 "$PROJ/install/opencode-go-proxy" /usr/local/bin/opencode-go-proxy
run install -m 0644 "$PROJ/install/opencode-go-proxy.service" /etc/systemd/system/opencode-go-proxy.service
say "已部署 opencode-go-proxy + systemd unit"
say "注意：代理从 $KEYFILE 读取密钥，install 目录里的 env 是占位符，不覆盖真实文件"

# ---------- 2. LiteLLM（:4000）----------
step "2. 部署 LiteLLM（:4000）"
if [[ -x /opt/litellm-venv/bin/litellm ]]; then
  run mkdir -p /opt/litellm
  run cp "$PROJ/install/litellm/config.yaml" /opt/litellm/config.yaml
  run install -m 0644 "$PROJ/install/litellm.service" /etc/systemd/system/litellm.service
  say "已部署 LiteLLM 配置与 systemd unit"
else
  say "✗ /opt/litellm-venv 不存在，跳过。重建方法："
  say "    python3 -m venv /opt/litellm-venv"
  say "    /opt/litellm-venv/bin/pip install 'litellm[proxy]'"
fi

# ---------- 3. 前端超时补丁 ----------
step "3. 部署 codeg 前端超时补丁"
run install -m 0755 "$PROJ/install/codeg-web-timeout-patch" /usr/local/bin/codeg-web-timeout-patch
if [[ -d /etc/systemd/system/codeg.service.d ]]; then
  cat > /etc/systemd/system/codeg.service.d/10-web-timeout-patch.conf <<'EOF'
[Service]
ExecStartPre=/usr/local/bin/codeg-web-timeout-patch
EOF
  say "已安装 codeg 开机自动重打补丁的 drop-in"
else
  say "✗ 未找到 codeg.service.d，跳过（如需要请手动创建）"
fi

# ---------- 4. codeg.env ----------
step "4. 还原 /etc/codeg.env"
ENV_SRC="$PROJ/config/codeg.env"
if [[ -f /etc/codeg.env ]]; then
  if (( DRY )); then say "[dry-run] 备份原 /etc/codeg.env"
  else cp /etc/codeg.env "/etc/codeg.env.bak.$(date +%s)"; say "已备份原 /etc/codeg.env"; fi
fi
# 保留原 token，其余按快照还原
CUR_TOKEN="$(grep -E '^CODEG_TOKEN=' /etc/codeg.env 2>/dev/null | cut -d= -f2- || true)"
run cp "$ENV_SRC" /etc/codeg.env
if [[ -n "$CUR_TOKEN" ]]; then
  if (( DRY )); then say "[dry-run] 保留原 CODEG_TOKEN"; else
    sed -i "s|^CODEG_TOKEN=.*|CODEG_TOKEN=$CUR_TOKEN|" /etc/codeg.env
    say "已保留原 CODEG_TOKEN"
  fi
fi

# ---------- 5. 各 agent 配置 ----------
step "5. 还原各 agent 配置（密钥统一写 local）"
restore_agent() {  # $1=源文件 $2=目标文件
  local src="$1" dst="$2"
  if [[ ! -f "$src" ]]; then say "跳过（快照缺失）：$src"; return; fi
  if [[ -f "$dst" ]]; then
    if (( DRY )); then say "[dry-run] 备份 $dst"
    else cp "$dst" "$dst.bak.$(date +%s)"; fi
  fi
  run install -D -m 0644 "$src" "$dst"
  say "→ $dst"
}
restore_agent "$PROJ/config/claude/settings.json"        /root/.claude/settings.json
restore_agent "$PROJ/config/codex/config.toml"           /root/.codex/config.toml
restore_agent "$PROJ/config/kimi-code/config.toml"       /root/.kimi-code/config.toml
restore_agent "$PROJ/config/hermes/config.yaml"          /root/.hermes/config.yaml
restore_agent "$PROJ/config/opencode/opencode.jsonc"     /root/.config/opencode/opencode.jsonc
restore_agent "$PROJ/config/settings.json"                /root/.pi/agent/settings.json
restore_agent "$PROJ/config/cline-providers.json"        /root/.cline/data/settings/providers.json

# opencode / pi 的 auth.json 里存真实 key，从活文件复制而不是用快照
step "6. 还原 agent 凭据文件（从现网复制，避免动 key）"
for f in /root/.local/share/opencode/auth.json /root/.pi/agent/auth.json; do
  if [[ -f "$f" ]]; then say "保留现网凭据： $f"; else say "⚠ $f 不存在，需手动重建"; fi
done

# ---------- 7. codeg 应用配置（SQLite，需先停 codeg）----------
step "7. 还原 codeg 应用配置（agent_setting / model_provider / app_metadata …）"
if [[ -d "$PROJ/codeg-app" ]]; then
  if (( DRY )); then
    say "[dry-run] systemctl stop codeg"
    say "[dry-run] python3 $PROJ/import_codeg_db.py   # 写回配置表"
    say "[dry-run] systemctl start codeg"
  else
    say "停止 codeg（写库前必须停）…"
    systemctl stop codeg
    sleep 3
    if python3 "$PROJ/import_codeg_db.py" "$PROJ/codeg-app"; then
      say "配置表已写回"
    else
      say "✗ 写回失败，保持 codeg 停止状态，请手动检查后 systemctl start codeg"
    fi
    systemctl start codeg
    say "已启动 codeg"
  fi
else
  say "⚠ 未找到 codeg-app/ 目录，跳过"
fi

# ---------- 8. 重启 ----------
step "8. 重启网关服务"
if (( DRY )); then
  say "[dry-run] systemctl daemon-reload"
  say "[dry-run] systemctl restart opencode-go-proxy litellm"
else
  systemctl daemon-reload
  systemctl restart opencode-go-proxy
  if [[ -x /opt/litellm-venv/bin/litellm ]]; then systemctl restart litellm; fi
  say "已重启 opencode-go-proxy / litellm"
  say "codeg 已在第 7 步重启过"
fi

# ---------- 9. 验证 ----------
step "9. 验证"
if (( ! DRY )); then
  sleep 5
  for s in opencode-go-proxy litellm; do
    printf '  %-20s %s\n' "$s" "$(systemctl is-active "$s" 2>/dev/null || echo 未安装)"
  done
  say ""
  say "端到端自检："
  if curl -sf --max-time 20 http://127.0.0.1:8899/v1/chat/completions \
      -H 'Content-Type: application/json' -H 'Authorization: Bearer local' \
      -d '{"model":"space-bunny-free","messages":[{"role":"user","content":"hi"}],"max_tokens":16}' >/dev/null 2>&1; then
    say "  ✓ :8899 代理 → opencode-go 正常"
  else
    say "  ✗ :8899 代理异常，检查 systemctl status opencode-go-proxy"
  fi
  if curl -sf --max-time 20 http://127.0.0.1:4000/health/liveliness >/dev/null 2>&1; then
    say "  ✓ :4000 LiteLLM 正常"
  else
    say "  ✗ :4000 LiteLLM 异常"
  fi
fi

echo
if (( DRY )); then
  echo "预览完成，未做任何修改。去掉 --dry-run 实际执行。"
else
  echo "全部完成。codeg 已在第 7 步重启，agent 配置已生效。"
fi
