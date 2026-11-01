#!/bin/bash
# audit.sh — 穷举审计：找出可能漏迁的自定义文件
set -u
TARGET=root@150.109.241.115
OUT=/root/codeg-work/audit-report.txt
: > "$OUT"
say(){ echo "$*" | tee -a "$OUT"; }
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=15)

say "================ 穷举审计 $(date '+%F %T') ================"

# ---------- 1. /etc 下"不属于任何包"的文件 ----------
say ""
say "【1】/etc 自定义文件（不属于任何 deb 包）"
cat /var/lib/dpkg/info/*.list 2>/dev/null | sed 's:/$::' | LC_ALL=C sort -u > /tmp/owned-src.txt
find /etc -type f 2>/dev/null | LC_ALL=C sort > /tmp/etc-src.txt
comm -23 /tmp/etc-src.txt /tmp/owned-src.txt > /tmp/etc-custom-src.txt
say "  源机 /etc 自定义文件: $(wc -l < /tmp/etc-custom-src.txt) 个"

"${SSH[@]}" "$TARGET" 'cat /var/lib/dpkg/info/*.list 2>/dev/null | sed "s:/$::" | LC_ALL=C sort -u > /tmp/owned-dst.txt
find /etc -type f 2>/dev/null | LC_ALL=C sort > /tmp/etc-dst.txt
comm -23 /tmp/etc-dst.txt /tmp/owned-dst.txt > /tmp/etc-custom-dst.txt
wc -l < /tmp/etc-custom-dst.txt' > /tmp/n-dst 2>/dev/null
say "  目标机 /etc 自定义文件: $(cat /tmp/n-dst | tr -d ' ') 个"

scp -q -o BatchMode=yes "$TARGET:/tmp/etc-custom-dst.txt" /tmp/etc-custom-dst.txt 2>/dev/null
comm -23 /tmp/etc-custom-src.txt /tmp/etc-custom-dst.txt > /tmp/etc-missing.txt
miss=$(wc -l < /tmp/etc-missing.txt)
say "  ❗源机有、目标机没有: $miss 个"
[ "$miss" -gt 0 ] && head -40 /tmp/etc-missing.txt | sed 's/^/      /' | tee -a "$OUT"

# ---------- 2. /usr/local 全量路径比对 ----------
say ""
say "【2】/usr/local 路径比对"
find /usr/local -mindepth 1 2>/dev/null | LC_ALL=C sort > /tmp/ul-src.txt
"${SSH[@]}" "$TARGET" 'find /usr/local -mindepth 1 2>/dev/null | LC_ALL=C sort' > /tmp/ul-dst.txt 2>/dev/null
say "  源 $(wc -l < /tmp/ul-src.txt) 项 / 目标 $(wc -l < /tmp/ul-dst.txt) 项"
comm -23 /tmp/ul-src.txt /tmp/ul-dst.txt > /tmp/ul-missing.txt
say "  ❗源有目标无: $(wc -l < /tmp/ul-missing.txt) 项"
head -20 /tmp/ul-missing.txt | sed 's/^/      /' | tee -a "$OUT"
say "  目标多出: $(comm -13 /tmp/ul-src.txt /tmp/ul-dst.txt | wc -l) 项（腾讯云基线）"

# ---------- 3. /opt 全量路径比对 ----------
say ""
say "【3】/opt 路径比对"
find /opt -mindepth 1 2>/dev/null | LC_ALL=C sort > /tmp/opt-src.txt
"${SSH[@]}" "$TARGET" 'find /opt -mindepth 1 2>/dev/null | LC_ALL=C sort' > /tmp/opt-dst.txt 2>/dev/null
say "  源 $(wc -l < /tmp/opt-src.txt) 项 / 目标 $(wc -l < /tmp/opt-dst.txt) 项"
comm -23 /tmp/opt-src.txt /tmp/opt-dst.txt > /tmp/opt-missing.txt
say "  ❗源有目标无: $(wc -l < /tmp/opt-missing.txt) 项"
head -20 /tmp/opt-missing.txt | sed 's/^/      /' | tee -a "$OUT"

# ---------- 4. 定时任务 ----------
say ""
say "【4】定时任务"
say "  源:"
for p in /var/spool/cron/crontabs/root /etc/crontab; do [ -f "$p" ] && say "    $p ($(wc -l < $p) 行)"; done
ls /etc/cron.d/ 2>/dev/null | sed 's/^/    \/etc\/cron.d\//' | tee -a "$OUT"
say "  目标:"
"${SSH[@]}" "$TARGET" 'for p in /var/spool/cron/crontabs/root /etc/crontab; do [ -f "$p" ] && echo "    $p ($(wc -l < $p) 行)"; done; ls /etc/cron.d/ 2>/dev/null | sed "s|^|    /etc/cron.d/|"' | tee -a "$OUT"

# ---------- 5. systemd 自定义单元 ----------
say ""
say "【5】systemd 自定义单元（非包安装）"
for u in /etc/systemd/system/*.service /etc/systemd/system/*.timer; do
  [ -e "$u" ] || continue
  dpkg -S "$u" >/dev/null 2>&1 && continue
  printf "    源有: %s\n" "$(basename "$u")" | tee -a "$OUT"
done
