#!/bin/bash
# migrate-stage3.sh — 在目标机上跑：收尾（权限、软链、swap、nginx 临时 HTTP、启服务、自检）
set -u
say(){ echo "[$(date +%T)] $*"; }

say "=== 1. 密钥文件权限 ==="
for f in /etc/codeg.env /etc/commandcode-proxy.env /etc/opencode-go-proxy.env \
         /etc/deepseek-official-key /etc/volcengine-ark-key; do
  [ -f "$f" ] && chmod 600 "$f" && echo "  600 $f"
done
[ -d /etc/letsencrypt ] && chmod -R go-rwx /etc/letsencrypt/archive /etc/letsencrypt/live /etc/letsencrypt/accounts 2>/dev/null

say "=== 2. 重建 /usr/bin 软链（node 全局包） ==="
python3 -I - <<'PY'
import json, glob, os
n = 0
for pj in glob.glob('/usr/lib/node_modules/*/package.json') + glob.glob('/usr/lib/node_modules/@*/*/package.json'):
    try: d = json.load(open(pj))
    except Exception: continue
    bins = d.get('bin')
    if not bins: continue
    if isinstance(bins, str): bins = {(d.get('name') or 'x').split('/')[-1]: bins}
    base = os.path.dirname(pj)
    for name, rel in bins.items():
        link = '/usr/bin/' + name
        if os.path.lexists(link): continue
        src = os.path.normpath(os.path.join(base, rel))
        if not os.path.exists(src): print('  ! 源不存在', src); continue
        os.symlink(src, link); n += 1
print('  新建软链', n, '条')
PY
ln -sf /usr/lib/node_modules/npm/bin/npm-cli.js /usr/bin/npm 2>/dev/null
ln -sf /usr/lib/node_modules/npm/bin/npx-cli.js /usr/bin/npx 2>/dev/null
ln -sfn /usr/lib/node_modules/corepack/dist/corepack.js /usr/bin/corepack 2>/dev/null

say "=== 3. swap ==="
if ! swapon --show | grep -q .; then
  MEM=$(free -m | awk '/Mem:/{print $2}')
  if [ "$MEM" -lt 6144 ]; then
    fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
    chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    sysctl -qw vm.swappiness=10
    echo "/swapfile none swap sw 0 0" > /etc/sysctl.d/99-swap.conf
    echo "  swap 已建: $(swapon --show=size --noheadings)"
  fi
else
  echo "  swap 已存在: $(swapon --show=size --noheadings | tr '\n' ' ')"
fi

say "=== 4. litellm venv 自检 ==="
if /opt/litellm-venv/bin/python -V 2>/dev/null; then
  /opt/litellm-venv/bin/litellm --version 2>&1 | head -1
else
  echo "  ! venv 不可用，需要重建"
fi

say "=== 5. nginx 临时 HTTP 入口（IP 直连，域名切换前用） ==="
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
cat > /etc/nginx/sites-available/codeg-ip <<'EOF'
# 临时：域名切换前，用 http://<公网IP>/ 直接访问 CodeG（迁移完成后删除本文件）
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    client_max_body_size 0;

    proxy_http_version 1.1;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host  $host;
    proxy_set_header Upgrade    $http_upgrade;
    proxy_set_header Connection "upgrade";

    proxy_buffering    off;
    proxy_cache        off;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;

    location / {
        proxy_pass http://127.0.0.1:3080;
    }
}
EOF
ln -sfn /etc/nginx/sites-available/codeg-ip /etc/nginx/sites-enabled/codeg-ip
ln -sfn /etc/nginx/sites-available/codeg    /etc/nginx/sites-enabled/codeg 2>/dev/null
nginx -t 2>&1 | tail -2

say "=== 6. 启用服务 ==="
systemctl daemon-reload
for s in codeg-port-lockdown opencode-go-proxy litellm commandcode-proxy codeg nginx; do
  systemctl enable --now "$s" >/dev/null 2>&1 && echo "  started $s" || {
    echo "  ! $s 启动失败:"; systemctl status "$s" --no-pager -l 2>&1 | tail -5; }
done
systemctl reload nginx 2>/dev/null || systemctl restart nginx

say "=== 7. 自检 ==="
sleep 5
ss -lntp | grep -E ':(80|443|3080|4000|8899)\b'
TOKEN=$(grep '^CODEG_TOKEN=' /etc/codeg.env | cut -d= -f2)
curl -sS --max-time 20 -X POST http://127.0.0.1:3080/api/acp_list_agents \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" -d '{}' \
  | head -c 400
echo
echo "  codeg 会话数: $(sqlite3 /root/.local/share/codeg/codeg.db 'select count(*) from sessions' 2>/dev/null || echo '?')"
say "=== stage3 ALL DONE ==="
