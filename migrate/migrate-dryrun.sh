#!/bin/bash
# 干跑：只看会删什么、会传什么，不动任何文件
TARGET=root@150.109.241.115
SSHOPT="ssh -o BatchMode=yes -o ConnectTimeout=15"
OUT=/root/codeg-work/dryrun-report.txt
: > "$OUT"
say(){ echo "$*" | tee -a "$OUT"; }

DIRS=(/root /usr/local/bin /usr/local/sbin /usr/local/go /usr/local/share/codeg
      /usr/local/share/codeg-opencode-quota /opt/litellm /opt/litellm-venv
      /opt/nvim-linux-x86_64 /var/www /var/lib/docker /usr/lib/node_modules
      /etc/nginx /etc/letsencrypt)

say "===== 干跑：$(date '+%F %T') ====="
for d in "${DIRS[@]}"; do
  [ -d "$d" ] || continue
  dst="${d%/}"
  case "$dst" in ""|"/") say "!!! 跳过根目录 $d"; continue;; esac
  out=$(rsync -aHAX --numeric-ids -n --delete --itemize-changes \
        -e "$SSHOPT" "$d/" "$TARGET:$dst/" 2>&1)
  del=$(printf '%s\n' "$out" | grep -c '^\*deleting')
  add=$(printf '%s\n' "$out" | grep -cE '^>f|^cd|^cL')
  say "$(printf '%-42s 待传 %6s   待删 %6s' "$d" "$add" "$del")"
  if [ "$del" != "0" ]; then
    printf '%s\n' "$out" | grep '^\*deleting' | head -8 | sed 's/^\*deleting/     删除:/' | tee -a "$OUT"
    [ "$del" -gt 8 ] && say "     ...(共 $del 项)"
  fi
done
say "===== 干跑结束 ====="
