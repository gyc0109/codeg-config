#!/usr/bin/env bash
# codeg 多模型路由 —— macOS (Apple Silicon / Intel) 一键部署
#
#   ./deploy-macos.sh            交互式（缺什么会提示）
#   ./deploy-macos.sh --dry-run  预览
#
# 与 Linux 版的差异：
#   · 不改系统 PATH / /etc（macOS 桌面版 codeg 不读 /etc/codeg.env）
#   · 前端超时补丁默认跳过（桌面版 web 打包在 .app 内，改它会被签名保护挡住）
#   · 服务用 launchd（如果装了 brew）否则给出手动启动命令
#   · agent 配置落在 ~/ 下，权限 600
set -euo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1
PORT_PROXY=8899
PORT_LLM=4000
SAY=0

say()  { (( SAY )) && printf '  %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; SAY=1; }
run()  { if (( DRY )); then say "[dry-run] $*"; else "$@"; fi; }

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

command -v brew >/dev/null && HAVE_BREW=1 || HAVE_BREW=0

# ---------- 0. 前置检查 ----------
step "0. 环境检查"
[[ "$(uname)" == "Darwin" ]] || die "这个脚本只能在 macOS 上跑（当前: $(uname)）"
ok "系统: $(sw_vers -productName) $(sw_vers -productVersion)"

PY=""
for c in python3.13 python3.12 python3.11 python3; do
  if command -v "$c" >/dev/null; then
    v=$("$c" -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null || echo 0)
    case "$v" in 3.1[0-9]) PY="$c"; break;; esac
  fi
done
[[ -n "$PY" ]] || die "需要 Python 3.10+（brew install python@3.12）"
ok "Python: $PY ($($PY -V 2>&1))"

[[ -x "$PROJ/install/opencode-go-proxy" ]] || [[ -f "$PROJ/install/opencode-go-proxy" ]] \
  || die "缺少 install/opencode-go-proxy，请先 git clone 本仓库"
"$PY" -c "import ast;ast.parse(open('$PROJ/install/opencode-go-proxy').read())" 2>/dev/null \
  && ok "代理脚本语法正确（纯标准库，macOS 兼容）"

# 端口占用
for p in $PORT_PROXY $PORT_LLM; do
  if lsof -nP -iTCP:$p -sTCP:LISTEN >/dev/null 2>&1; then
    warn "端口 $p 已被占用：$(lsof -nP -iTCP:$p -sTCP:LISTEN -t | head -1 | xargs -I{} ps -p {} -o comm= 2>/dev/null)"
  fi
done

# ---------- 1. 密钥 ----------
step "1. 配置 OpenCode Go 密钥"
KEYFILE="$HOME/.config/codeg/opencode-go.env"
if [[ -f "$KEYFILE" ]] && grep -qE '^OPENCODE_GO_API_KEY=.+' "$KEYFILE"; then
  K=$(grep '^OPENCODE_GO_API_KEY=' "$KEYFILE" | cut -d= -f2-)
  ok "已存在: ${K:0:10}…${K: -4}"
else
  printf '  请粘贴 OpenCode Go 的 API key（oc_sk_… 或 sk-…）\n'
  printf '  获取地址: https://opencode.ai/zen  →  API Keys\n'
  read -r -s -p "  key: " NEWKEY; echo
  [[ "$NEWKEY" == *"-sk-"* || "$NEWKEY" == oc_sk_* || "$NEWKEY" == sk-* ]] \
    || die "key 格式看起来不对"
  run bash -c "mkdir -p '$HOME/.config/codeg' && umask 077 && printf 'OPENCODE_GO_API_KEY=%s\n' '$NEWKEY' > '$KEYFILE'"
  run chmod 600 "$KEYFILE"
  ok "已写入 $KEYFILE (600)"
fi

# ---------- 2. 代理 :8899 ----------
step "2. 部署 opencode-go-proxy (:$PORT_PROXY)"
BIN="$HOME/.local/bin/opencode-go-proxy"
run mkdir -p "$HOME/.local/bin"
run cp "$PROJ/install/opencode-go-proxy" "$BIN"
run chmod 755 "$BIN"
ok "→ $BIN"

# ---------- 3. LiteLLM :4000 ----------
step "3. 部署 LiteLLM (:$PORT_LLM)"
VENV="$HOME/.local/share/codeg/litellm-venv"
if [[ -x "$VENV/bin/litellm" ]]; then
  ok "已存在: $("$VENV/bin/litellm" --version 2>&1 | head -1)"
else
  if (( DRY )); then
    say "[dry-run] $PY -m venv $VENV"
    say "[dry-run] $VENV/bin/pip install 'litellm[proxy]'"
  else
    say "首次安装约 3~5 分钟，请耐心等待…"
    "$PY" -m venv "$VENV"
    "$VENV/bin/pip" install -q -U pip
    "$VENV/bin/pip" install -q "litellm[proxy]"
    ok "已安装: $("$VENV/bin/litellm" --version 2>&1 | head -1)"
  fi
fi
run mkdir -p "$HOME/.local/share/codeg/litellm"
run cp "$PROJ/install/litellm/config.yaml" "$HOME/.local/share/codeg/litellm/config.yaml"
ok "→ \$HOME/.local/share/codeg/litellm/config.yaml"

# ---------- 4. 启动脚本 ----------
step "4. 生成启动脚本"
START="$HOME/.local/share/codeg/start-gateways.sh"
run mkdir -p "$HOME/.local/share/codeg"
if (( ! DRY )); then
cat > "$START" <<EOF
#!/usr/bin/env bash
# codeg 多模型路由网关（代理 $PORT_PROXY + LiteLLM $PORT_LLM）
set -u
export OPENCODE_GO_API_KEY="\$(grep '^OPENCODE_GO_API_KEY=' '$KEYFILE' | cut -d= -f2-)"
export PATH="/usr/local/bin:/opt/homebrew/bin:\$HOME/.local/bin:\$PATH"
pkill -f 'opencode-go-proxy' 2>/dev/null
pkill -f 'litellm --config' 2>/dev/null
sleep 1
nohup "$BIN" > "$HOME/.local/share/codeg/proxy.log" 2>&1 &
sleep 2
nohup "$VENV/bin/litellm" --config "$HOME/.local/share/codeg/litellm/config.yaml" \\
      --host 127.0.0.1 --port $PORT_LLM --num_workers 1 \\
      > "$HOME/.local/share/codeg/litellm.log" 2>&1 &
sleep 8
echo "代理  :$PORT_PROXY  \$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://127.0.0.1:$PORT_PROXY/v1/models || echo ERR)"
echo "LiteLLM :$PORT_LLM  \$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://127.0.0.1:$PORT_LLM/health/liveliness || echo ERR)"
EOF
  chmod +x "$START"
  ok "→ $START"
  say "运行它即可启动两个网关： $START"
fi

if (( HAVE_BREW )); then
  step "5. 注册为开机自启 (launchd)"
  PLIST="$HOME/Library/LaunchAgents/app.codeg.gateways.plist"
  run mkdir -p "$HOME/Library/LaunchAgents"
  if (( ! DRY )); then
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>app.codeg.gateways</string>
  <key>ProgramArguments</key><array><string>$START</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/.local/share/codeg/gateways.out.log</string>
  <key>StandardErrorPath</key><string>$HOME/.local/share/codeg/gateways.err.log</string>
</dict></plist>
EOF
    say "[dry-run] launchctl bootstrap gui/\$(id -u) $PLIST"
  else
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null \
      && ok "已注册开机自启： app.codeg.gateways" \
      || warn "注册失败，手动运行 $START 即可"
  fi
else
  step "5. 开机自启"
  warn "未装 Homebrew，跳过 launchd 注册"
  say "手动启动： $START"
fi

# ---------- 6. agent 配置 ----------
step "6. 写入 agent 配置"
CFG="$HOME/.config/codeg/agents"
run mkdir -p "$CFG/claude" "$CFG/codex" "$CFG/kimi-code" "$CFG/hermes" "$CFG/opencode"
for f in claude/settings.json codex/config.toml kimi-code/config.toml hermes/config.yaml opencode/opencode.jsonc; do
  run cp "$PROJ/config/$f" "$CFG/$f"
done
ok "配置副本 → $CFG"

cat <<'EOF'

  接下来在 codeg 桌面端「设置 → Agent」里配置（把占位符 local 换成你的 key）：

  ┌─ 直接接代理 :8899（8 个 chat agent 通用）────────────────────┐
  │  api_base_url : http://127.0.0.1:8899/v1                    │
  │  api_key      : local                                      │
  │  model        : space-bunny-free   (免费)                  │
  │               deepseek-v4.1-flash  ($0.15/$0.6)             │
  │               qwen3.8-flash       ($0.15/$0.47)            │
  │               mimo-v2.6-flash     ($0.14/$0.28)            │
  │               glm-5.3-flash       ($0.15/$0.5)             │
  └───────────────────────────────────────────────────────────┘

  ┌─ 经 LiteLLM :4000（Claude Code / Codex 专用）───────────────┐
  │  api_base_url : http://127.0.0.1:4000                      │
  │  api_key      : local                                      │
  │  model        : deepseek-v4.1-flash  (Codex 需 wire_api=responses)│
  │               mimo-v2.5 / glm-5.3 / qwen3.8-max …         │
  └───────────────────────────────────────────────────────────┘

  ⚠️ macOS 注意：npm 全局目录在 /opt/homebrew/bin（Apple Silicon）
     请确认 codeg 能找到 agent：which claude-agent-acp codex-acp pi-acp
     找不到就把 /opt/homebrew/bin 加进 codeg 的 PATH。

EOF

step "完成"
printf '  网关状态：\n'
if (( ! DRY )); then
  printf '    代理   :%s  %s\n' "$PORT_PROXY" \
    "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:$PORT_PROXY/v1/models" 2>/dev/null || echo 未启动)"
  printf '    LiteLLM:%s  %s\n' "$PORT_LLM" \
    "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:$PORT_LLM/health/liveliness" 2>/dev/null || echo 未启动)"
else
  say "（dry-run，未实际验证）"
fi
echo
echo "  下一步：打开 codeg 桌面端，按上面表格配置模型"
echo
