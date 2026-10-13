#!/bin/bash
# 给本机 codeg 装 skill 的完整流程
#
#   1) 备份
#   2) 确保 skills CLI 装好并已打 codeg 补丁
#   3) 用 CLI 装 skill
#   4) 归一化布局（CLI 的约定和 codeg 相反）
#   5) 验证
#
# 用法: install-skills.sh <owner/repo> <skill名> [更多 owner/repo skill名 ...]
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "用法: $0 <owner/repo> <skill名> [<owner/repo> <skill名> ...]" >&2
  exit 1
fi

echo "═══ 1) 备份 ═══"
BK="$HOME/codeg-skills-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BK"
cp -a "$HOME/.codeg/skills" "$BK/codeg-skills"
for d in .claude/skills .pi/agent/skills .codex/skills .config/opencode/skills \
         .hermes/skills .kimi-code/skills .openclaw/skills .agents/skills \
         .codebuddy/skills .dsh/skills; do
  ls -la "$HOME/$d" > "$BK/links-$(echo "$d" | tr '/' '_').txt" 2>/dev/null || true
done
echo "  → $BK"

echo
echo "═══ 2) skills CLI ═══"
if ! command -v skills >/dev/null 2>&1; then
  npm install -g --registry=https://registry.npmmirror.com skills
fi
skills --version
# 补丁（npm update 会覆盖，所以每次都检查）
if ! grep -q 'displayName: "codeg"' "$(npm root -g)/skills/dist/cli.mjs" 2>/dev/null; then
  echo "  补丁丢失（可能被 npm update 覆盖），重新打..."
  python3 "$(dirname "$0")/patch-skills-cli.py"
fi

echo
echo "═══ 3) 安装 ═══"
while [ $# -ge 2 ]; do
  repo="$1"; sk="$2"; shift 2
  echo "  ── $repo @ $sk ──"
  skills add "$repo" --skill "$sk" -g -a '*' -y 2>&1 \
    | sed 's/\x1b\[[0-9;]*m//g' | grep -vE '^\s*$' | tail -6 | sed 's/^/    /'
done

echo
echo "═══ 4) 归一化布局 ═══"
python3 "$(dirname "$0")/normalize-skills-layout.py"

echo
echo "═══ 5) 验证 ═══"
for d in .codeg/skills .claude/skills .pi/agent/skills .codex/skills .config/opencode/skills \
         .hermes/skills .kimi-code/skills .openclaw/skills .agents/skills .codebuddy/skills .dsh/skills; do
  printf '  %-30s %s\n' "$d" "$(ls "$HOME/$d" 2>/dev/null | grep -vc '^\.')"
done
echo
echo "  ⚠ skill 列表在会话启动时注入，装完要开新会话才看得到"
