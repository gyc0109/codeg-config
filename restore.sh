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
say "OpenCode Go 密钥已就绪（${KEY:0:6}…${KEY: -4}）"
say "LiteLLM 解释器： $( [[ -x /opt/litellm-venv/bin/litellm ]] && echo 存在 || echo '缺失，需重新安装' )"

# Command Code GOAT 是可选第二个供应商：只有配了才启用
CCKEYFILE=/etc/commandcode-proxy.env
CCKEY=""
if [[ -f "$CCKEYFILE" ]]; then
  CCKEY="$(grep -E '^COMMANDCODE_API_KEY=' "$CCKEYFILE" | cut -d= -f2- | tr -d '\"\047' || true)"
  if [[ -n "$CCKEY" && "$CCKEY" != *填入* ]]; then
    say "Command Code 密钥已就绪（${CCKEY:0:9}…${CCKEY: -4}）"
  else
    say "⚠ $CCKEYFILE 存在但 key 未填写，将跳过 Command Code 相关配置"
    CCKEY=""
  fi
else
  say "未发现 $CCKEYFILE —— 只还原 OpenCode Go，跳过 Command Code"
fi

# ---------- 1. 代理（:8899）----------
step "1. 部署 opencode-go-proxy（:8899）"
run install -m 0755 "$PROJ/install/opencode-go-proxy" /usr/local/bin/opencode-go-proxy
run install -m 0644 "$PROJ/install/opencode-go-proxy.service" /etc/systemd/system/opencode-go-proxy.service
say "已部署 opencode-go-proxy + systemd unit"
say "注意：代理从 $KEYFILE 读取密钥，install 目录里的 env 是占位符，不覆盖真实文件"

# ---------- 1b. Command Code 代理（:8898，Claude Code 专用）----------
if [[ -n "$CCKEY" ]]; then
  step "1b. 部署 commandcode-proxy（:8898）"
  run install -m 0755 "$PROJ/install/commandcode-proxy" /usr/local/bin/commandcode-proxy
  run install -m 0644 "$PROJ/install/commandcode-proxy.service" /etc/systemd/system/commandcode-proxy.service
  say "已部署 commandcode-proxy + systemd unit"
  say "作用：Claude Code 会把 system 角色塞进 messages，Command Code 会 400 拒绝；"
  say "      该代理把 system 提到顶层，并注入真实 key。"
else
  step "1b. 跳过 commandcode-proxy（未配置 Command Code 密钥）"
fi

# ---------- 2. LiteLLM（:4000）----------
step "2. 部署 LiteLLM（:4000）"
if [[ -x /opt/litellm-venv/bin/litellm ]]; then
  run mkdir -p /opt/litellm
  # 快照里 Command Code 的 api_key 是 ${COMMANDCODE_API_KEY} 占位符，写入前注入真实 key
  if (( DRY )); then
    say "[dry-run] 注入 Command Code key 后写入 /opt/litellm/config.yaml"
  else
    sed -e "s|\${COMMANDCODE_API_KEY}|${CCKEY}|g" \
        -e "s|\${OPENCODE_GO_API_KEY}|${KEY}|g" \
        "$PROJ/install/litellm/config.yaml" > /opt/litellm/config.yaml
    say "已写入 /opt/litellm/config.yaml（已注入密钥）"
  fi
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

# ---------- 3b. pi-acp 分组名补丁 ----------
step "3b. 部署 pi-acp provider 显示名补丁"
if [[ -f /usr/lib/node_modules/pi-acp/dist/index.js ]]; then
  run install -m 0755 "$PROJ/install/pi-acp-provider-label-patch" /usr/local/bin/pi-acp-provider-label-patch
  run install -m 0644 "$PROJ/install/pi-acp-provider-label-dropin.conf" /etc/systemd/system/codeg.service.d/20-pi-acp-provider-label.conf
  if (( DRY )); then say "[dry-run] /usr/local/bin/pi-acp-provider-label-patch"
  else /usr/local/bin/pi-acp-provider-label-patch || say "⚠ 打补丁失败"; fi
  say "作用：pi 在 ACP 里把分组名从 provider id（ocg）改成可读名（OpenCode Go）；"
  say "      modelId（option.value）不变，所以 ocg/ 路由不受影响。"
else
  say "跳过（未安装 pi-acp）"
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
  local src="$1" dst="$2" tmp
  if [[ ! -f "$src" ]]; then say "跳过（快照缺失）：$src"; return; fi
  if [[ -f "$dst" ]]; then
    if (( DRY )); then say "[dry-run] 备份 $dst"
    else cp "$dst" "$dst.bak.$(date +%s)"; fi
  fi
  # 快照里的 ${...} 占位符 → 真实密钥（仓库里永远不存明文 key）
  tmp="$(mktemp)"
  sed -e "s|\${OPENCODE_GO_API_KEY}|${KEY}|g" \
      -e "s|\${COMMANDCODE_API_KEY}|${CCKEY}|g" "$src" > "$tmp"
  if (( DRY )); then say "[dry-run] install -D -m 0644 <已注入密钥> $dst"; rm -f "$tmp"
  else install -D -m 0644 "$tmp" "$dst"; rm -f "$tmp"; fi
  say "→ $dst"
}
restore_agent "$PROJ/config/claude/settings.json"        /root/.claude/settings.json
restore_agent "$PROJ/config/codex/config.toml"           /root/.codex/config.toml
restore_agent "$PROJ/config/kimi-code/config.toml"       /root/.kimi-code/config.toml
restore_agent "$PROJ/config/hermes/config.yaml"          /root/.hermes/config.yaml
restore_agent "$PROJ/config/opencode/opencode.jsonc"     /root/.config/opencode/opencode.jsonc
restore_agent "$PROJ/config/settings.json"                /root/.pi/agent/settings.json
restore_agent "$PROJ/config/pi/models.json"               /root/.pi/agent/models.json
restore_agent "$PROJ/config/cline-providers.json"        /root/.cline/data/settings/providers.json
restore_agent "$PROJ/config/codex-model-catalog.json"    /root/.codex/codeg-model-catalog.json

# ---------- 5b. open_claw（Gateway + 双 provider）----------
step "5b. 还原 OpenClaw（open_claw）"
if [[ -f "$PROJ/config/openclaw/openclaw.json" ]] && command -v openclaw >/dev/null 2>&1; then
  if (( DRY )); then say "[dry-run] 写入 ~/.openclaw/openclaw.json（注入 CC key）"
  else
    [[ -f /root/.openclaw/openclaw.json ]] && cp /root/.openclaw/openclaw.json "/root/.openclaw/openclaw.json.bak.$(date +%s)"
    mkdir -p /root/.openclaw
    sed -e "s|\${COMMANDCODE_API_KEY}|${CCKEY}|g" \
        -e "s|\${OPENCODE_GO_API_KEY}|${KEY}|g" \
        "$PROJ/config/openclaw/openclaw.json" > /root/.openclaw/openclaw.json
    chmod 600 /root/.openclaw/openclaw.json
    say "→ /root/.openclaw/openclaw.json"
  fi
  # ACP 桥接没有本地模式，必须靠 Gateway（loopback :18789）。
  # openclaw 会装成 systemd **user** 服务，但 root 默认没有 linger，
  # 开机/登出后会僵，所以必须 enable-linger。
  if (( DRY )); then
    say "[dry-run] openclaw gateway install && loginctl enable-linger root"
  else
    loginctl enable-linger root 2>/dev/null || true
    if ! systemctl --user is-enabled openclaw-gateway >/dev/null 2>&1; then
      XDG_RUNTIME_DIR=/run/user/0 openclaw gateway install >/dev/null 2>&1 || \
        say "⚠ Gateway 服务安装失败，手工执行：openclaw gateway install"
    else
      XDG_RUNTIME_DIR=/run/user/0 openclaw gateway restart >/dev/null 2>&1 || true
    fi
    say "Gateway 服务已就绪（linger=on）"
  fi
else
  say "跳过（无 openclaw 或快照缺失）"
fi

# opencode / pi 的 auth.json 里存真实 key，从活文件复制而不是用快照
step "6. 还原 agent 凭据文件（从现网复制，避免动 key）"
for f in /root/.local/share/opencode/auth.json /root/.pi/agent/auth.json; do
  if [[ -f "$f" ]]; then say "保留现网凭据： $f"; else say "⚠ $f 不存在，需手动重建"; fi
done
# pi 内置的 opencode-go provider 无法删除，会把模型列成 opencode-go/xxx；
# 从 auth.json 移除它的凭据就不显示了，统一用 models.json 里的 ocg/ 命名空间。
if [[ -f /root/.pi/agent/auth.json ]]; then
  if (( DRY )); then say "[dry-run] 移除 pi auth.json 里的 opencode-go（避免与 ocg 重复）"
  else
    python3 - <<'PY'
import json
p = "/root/.pi/agent/auth.json"
d = json.load(open(p))
dropped = [k for k in ("opencode-go", "commandcode") if d.pop(k, None) is not None]
if dropped:
    json.dump(d, open(p, "w"), indent=2)
    print("  ✓ pi auth.json 已移除：" + ", ".join(dropped))
else:
    print("  - pi auth.json 无多余条目，跳过")
PY
  fi
fi

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
    # model_provider 里的 Command Code key 导出时被脱敏成 ${REDACTED}，
    # 这里把指向 commandcode.ai 的行重新填上真实 key（其余行不动）。
    if [[ -n "$CCKEY" ]]; then
      python3 - "$CCKEY" <<'PY'
import sqlite3, sys
key = sys.argv[1]
db = "/root/.local/share/codeg/codeg.db"
c = sqlite3.connect(db)
n = c.execute(
    "UPDATE model_provider SET api_key=? WHERE api_url LIKE '%commandcode.ai%' AND (api_key=? OR api_key LIKE '%REDACTED%')",
    (key, "${REDACTED}"),
).rowcount
c.commit(); c.close()
print(f"  ✓ 已回填 Command Code key：{n} 个 provider")
PY
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
  if [[ -n "$CCKEY" ]]; then systemctl enable --now commandcode-proxy; fi
  say "已重启 opencode-go-proxy / litellm$([[ -n "$CCKEY" ]] && echo ' / commandcode-proxy')"
  say "codeg 已在第 7 步重启过"
fi

# ---------- 9. 验证 ----------
step "9. 验证"
if (( ! DRY )); then
  sleep 5
  for s in opencode-go-proxy litellm commandcode-proxy; do
    printf '  %-20s %s\n' "$s" "$(systemctl is-active "$s" 2>/dev/null || echo 未安装)"
  done
  if command -v openclaw >/dev/null 2>&1; then
    printf '  %-20s %s\n' "openclaw-gateway" "$(XDG_RUNTIME_DIR=/run/user/0 systemctl --user is-active openclaw-gateway 2>/dev/null || echo 未运行)"
  fi
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
  if [[ -n "$CCKEY" ]]; then
    if curl -sf --max-time 60 http://127.0.0.1:8898/v1/messages \
        -H 'Content-Type: application/json' -H 'x-api-key: local' -H 'anthropic-version: 2023-06-01' \
        -d '{"model":"claude-sonnet-5-5","max_tokens":16,"system":"t","messages":[{"role":"user","content":"hi"},{"role":"system","content":[{"type":"text","text":"ctx"}]}]}' >/dev/null 2>&1; then
      say "  ✓ :8898 代理 → Command Code 正常（system 角色已自动归并）"
    else
      say "  ✗ :8898 代理异常，检查 systemctl status commandcode-proxy"
    fi
  fi
fi

echo
if (( DRY )); then
  echo "预览完成，未做任何修改。去掉 --dry-run 实际执行。"
else
  echo "全部完成。codeg 已在第 7 步重启，agent 配置已生效。"
fi
