#!/bin/bash
# Mac 最终 agent 验证（正确路径）
export PATH="$HOME/.local/share/fnm/node-versions/v26.8.1/installation/bin:$PATH"
AC="$HOME/Library/Application Support/app.codeg"
OC="$AC/acp-binaries/opencode/1.19.0/darwin-aarch64/opencode"
P="$HOME/.pi/pi-acp"
PROMPT="Reply with exactly: PONG"

run() {
  local name="$1" secs="$2"; shift 2
  printf '  %-16s ' "$name"
  local out
  out=$(perl -e 'my $t=shift;my $p=fork();if($p==0){exec @ARGV;exit 127;}local $SIG{ALRM}=sub{kill "TERM",$p;exit 124;};alarm $t;waitpid($p,0);' "$secs" "$@" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
  if echo "$out" | grep -qE '(^| )PONG($| )'; then echo 'OK'
  else echo "FAIL: $(echo "$out" | grep -vE '^[[:space:]]*$' | tail -1 | cut -c1-70)"; fi
}

echo "═══ agent 实测 ═══"
run "pi"         200 "$P" -p "$PROMPT"
run "kimi"       200 kimi -p "$PROMPT"
run "hermes"     220 hermes -z "$PROMPT"
run "open_code"  200 "$OC" run --model ocg/longcat-2.5-preview-free "$PROMPT"
run "code_buddy" 220 codebuddy -p "$PROMPT"
run "grok"       220 grok -p "$PROMPT"
run "open_claw"  240 openclaw agent -m "$PROMPT"

echo
echo "═══ opencode 二进制确认 ═══"
ls -la "$OC" 2>/dev/null | sed 's/^/  /'
"$OC" --version 2>&1 | head -1 | sed 's/^/  version: /'
