# 整机配置迁移（codeg + agent + 模型路由）

把这台机器上的 codeg 配置、对话历史、agent 授权、模型路由、nginx/证书搬到另一台机器。
目标是**一摸一样**，不是重装再配。

三个脚本，两种用法：

| 用法 | 脚本 | 何时用 |
| --- | --- | --- |
| **直推**（推荐） | `migrate-push.sh` | 目标机已有 SSH。不占本地磁盘，边传边铺 |
| 打包再搬 | `migrate-export.sh` → `migrate-import.sh` | 目标机暂时连不上，或要留一份离线备份 |

源机只剩 8.5G，而全量 bundle 约 8.8G（node_modules 4.5G + acp-binaries 1.8G +
/usr/local 1.1G + /opt 0.7G + 配置 0.7G），**打包模式会撑爆磁盘**。所以优先直推。

---

## 直推（推荐）

在**源机**上：

```bash
cd /root/Labs/codeg-config/migrate
./migrate-push.sh root@<目标机IP> --dry-run   # 先看一眼要做什么
./migrate-push.sh root@<目标机IP>             # 真跑
```

前提：

- 目标机是**全新** Debian 13 x86_64，能 root SSH 登录（建议先 `ssh-copy-id` 配好免密，
  脚本用了 `BatchMode=yes`）
  - **为什么必须 13**：`/opt/litellm-venv` 是指向 `/usr/bin/python3.13` 的 venv，
    换到 Debian 12（python3.11）venv 直接不可用，得重建
  - 磁盘建议 ≥40G：迁完约 12G（系统 3G + 配置 8.6G），留出增长空间
- 目标机有 `rsync`（没有脚本会自动装）

脚本做的事：预检架构 → 装基础包 → 停目标机 codeg → 推 codeg.db 一致快照 →
推目录 → 远程重建 `/usr/bin` 软链、`daemon-reload`、按依赖顺序起服务 →
对比行数 + 调 `acp_list_agents` 验证。

传完之后**不要让两台同时对外服务**：它们共用同一份 token、同一批会话，指向上游
代理的密钥也一样。

正式搬之前建议在**源机停掉 codeg** 再跑最后一遍：

```bash
systemctl stop codeg
./migrate-push.sh root@<目标机IP>
```

否则推的过程中源机还在写会话正文（`.jsonl` 追加），拿到的可能是半截会话。
DB 那边脚本用了 `.backup`，不受影响；受影响的是各 agent 自己存的消息正文。

### `--slim`

跳过 `/usr/lib/node_modules`（4.5G）和 `acp-binaries`（1.8G）。目标机之后用
`meta/npm-globals.txt` 里的精确版本 `npm i -g` 补回来，binary agent 用
`acp_download_agent_binary` 重下。带宽紧张时用，但**不算「一摸一样」**，要补功课。

---

## 打包模式

源机上：

```bash
./migrate-export.sh /root/migrate-out          # 全量，需要 ~9G 空闲
./migrate-export.sh /root/migrate-out --slim   # 约 1/3 体积
```

产物结构：

```
bundle/
  rootfs/          按绝对路径铺好的文件树，rsync 到 / 即可
  meta/
    system.txt      源机 os/arch/node/python 版本
    sqlite/codeg.db 一致快照（不是活库拷贝）
    sqlite/rowcounts.txt   各表行数，导入后对比
    symlinks.txt    /usr/bin 下指向 node_modules 的软链图
    npm-globals.txt 全局 npm 包精确版本
    dpkg-selections.txt
    systemd/*.service.txt   单元原文
  MANIFEST.txt
```

拷到目标机后：

```bash
./migrate-import.sh <bundle目录>
```

---

## 四个必须知道的坑

### 1. 绝对路径绑定 — `/root/Labs/codeg-config` 不能换位置

agent 的会话目录是按 **cwd** 编码的（这台机器上实际长这样）：

```
~/.local/share/codeg/chat-sessions/2026-09-11/
~/.claude/projects/-root--local-share-codeg-chat-sessions-2026-09-11-<uuid>/
~/.claude/projects/-root-Labs-codeg-config/
```

搬到别的路径，codeg 里的历史对话就**点不开**（元数据在 db 里，正文在 agent 自己的
存储里，靠路径对上）。所以目标机上这个仓库要放在**同一个绝对路径**。

### 2. codeg.db 有 WAL，不能直接 `cp`

直接拷会拿到半写状态，`-wal` 里的事务可能丢。必须：

```bash
sqlite3 /root/.local/share/codeg/codeg.db ".backup '<目标>'"
```

两个脚本都是这么做的，并且导入后**删掉目标机上的旧 `-wal`/`-shm`**——
否则 sqlite 会拿旧 wal 回放，把刚铺好的数据覆盖回旧状态。

### 3. `/opt/litellm-venv` 里的绝对路径

venv 的 `bin/*` shebang 和 `pyvenv.cfg` 写死了 `/opt/litellm-venv/bin/python3`。
只要目标机也铺在 `/opt/litellm-venv`（脚本就是这么做的）就没事；换路径要重建 venv：

```bash
/usr/bin/python3 -m venv /opt/litellm-venv && /opt/litellm-venv/bin/pip install -r <requirements>
```

### 4. binary agent 绑定架构

`antigravity` / `cursor` / `open_code` 是下载的 ELF，x86_64 的不能拷到 ARM 机器上。
两个脚本都会预检 `uname -m`，不一致直接退出。

---

## 搬完要人工确认的

1. **域名与证书**：`/etc/nginx/sites-available/codeg` 里写的是 `gycai.top`。
   换域名要改 `server_name` 并重签；`/etc/letsencrypt` 里的证书带着原机的
   renewal 配置，换域名不能直接用。
2. **腾讯云安全组**：默认只开 22。要放行 80/443（nginx），
   3080 建议**不要**对公网开，走 nginx 反代。
3. **openclaw 是 `systemd --user` 单元**，要登录会话里手动起：
   ```bash
   systemctl --user enable --now openclaw-gateway
   loginctl enable-linger root      # 否则退出登录就停
   ```
4. **首次访问** codeg 用目标机 `/etc/codeg.env` 里的 `CODEG_TOKEN`。
5. **Docker / 其它服务**不在本迁移范围内（本机没装）。
6. 验证清单：
   ```bash
   systemctl is-active opencode-go-proxy litellm commandcode-proxy codeg
   ss -lntp | grep -E ':(3080|4000|8897|8898|8899)\b'
   curl -s -X POST http://127.0.0.1:3080/api/acp_list_agents \
     -H "Authorization: Bearer $CODEG_TOKEN" -d '{}' | jq length
   ```
   再挑一个 agent 跑一轮真实对话，确认历史对话能打开。

---

## 安全

bundle 和直推流量里都是**明文密钥**：

```
/etc/codeg.env                   CODEG_TOKEN
/etc/opencode-go-proxy.env       上游 API key
/etc/commandcode-proxy.env       上游 API key
/root/.claude.json               claude 登录态（600）
/root/.kiro/                      kiro 登录态
/root/.local/share/codeg/        会话正文 + acp-binaries
/etc/letsencrypt/live/*/privkey.pem
```

- **一律走 SSH**，别用 `scp` 到公网可访问的临时目录，别传网盘
- bundle 建完 `chmod 700` 输出目录，传完就删
- 目标机上 `/etc/*.env` 保持 `600`
- 迁移窗口内**源机先停服务**再取快照，避免搬过去之后又产生新对话
