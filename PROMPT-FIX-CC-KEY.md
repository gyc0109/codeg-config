# PROMPT-FIX-CC-KEY：ccg / Command Code 模型全 401 的定位与修复

用这个提示词，当**某台机器上 `ccg/*`（Command Code GOAT）模型突然全不可用**时用。
典型症状：Claude Code 每轮报 `Authentication required` / `authentication_failed (HTTP 401)`，
codex / opencode / openclaw / hermes / codebuddy 里凡是以 `ccg/` 开头的模型全部失败，
而 `ocg/`、`ds/`、`ark/` 前缀的模型一切正常。

整段复制给目标机器上的 agent：

```
read https://raw.githubusercontent.com/gyc0109/codeg-config/main/PROMPT-FIX-CC-KEY.md
按它的流程，把这台机器上 ccg/（Command Code GOAT）模型的 401 查清并修好。

我这台机器：<服务器 4.1 / MacBook / Windows>
代理由谁提供：<不确定，自己查 / LiteLLM :4000 / 自己写的 python 代理 :15825 / cc-switch :15721>
新的 Command Code key：<粘贴新 key，或用占位符 <NEW_KEY> 让我稍后填>

不要照抄文档里的路径，先自己探明这台机器的拓扑再动手。
改完给我实测结果（哪几个模型、哪个端点、HTTP 码），别只改配置。
```

---

## 第 0 步：先定性，别相信 `/models`

这是整件事最关键的一条，**已经踩过两次**：

```
GET  https://api.commandcode.ai/provider/v1/models          → 200，匿名也 200
POST https://api.commandcode.ai/provider/v1/chat/completions → 401 Invalid 'Authorization' header or token
```

所以「模型清单能拉到」「模型列表里有这个模型」**都不是 key 有效的证据**。
唯一的判据是打一次 completion：

```bash
CCKEY=<NEW_KEY>   # 或从本机 key 文件读，见第 1 步
curl -s -o /tmp/cc_probe.json -w '%{http_code}\n' \
  https://api.commandcode.ai/provider/v1/chat/completions \
  -H "Authorization: Bearer $CCKEY" -H 'content-type: application/json' \
  -d '{"model":"z-ai/glm-5.3-flash","max_tokens":64,"messages":[{"role":"user","content":"hi"}]}'
cat /tmp/cc_probe.json
```

| 结果 | 含义 |
| --- | --- |
| `200` | key 有效。问题在本机代理/配置层，跳到第 1 步看链路 |
| `401 Invalid 'Authorization' header or token` | **key 失效**，走第 2 步换 key |
| `403 MODEL_NOT_IN_PLAN` | key 有效但套餐不含该模型 — 换模型，不是 key 问题 |
| `429 temporarily unavailable` | 上游临时限流，通常只影响 `*:free` 模型，隔几分钟再试 |

## 第 1 步：画出这台机器的拓扑（不要照抄服务器路径）

先回答三个问题，再动手：

```bash
# 1) 有哪些本地端口在跑网关
ss -ltnp 2>/dev/null | grep -E ':(4000|8898|8899|15721|15825)\b' \
  || netstat -an | grep LISTEN

# 2) 谁在监听（进程 + 命令行，能看出是 litellm / python 代理 / cc-switch）
ps aux | grep -Ei 'litellm|proxy|codeg-server|cc-switch' | grep -v grep

# 3) 全盘找 Command Code 的真实 key 落在哪（这是关键，各平台路径完全不同）
grep -rl --binary-files=text 'api.commandcode.ai' \
  ~/.codeg ~/.claude ~/.codex ~/.config ~/.openclaw ~/.pi ~/.kimi-code \
  ~/.hermes ~/.codebuddy ~/Library/Application\ Support 2>/dev/null
grep -rl --binary-files=text 'user_[A-Za-z0-9]\{40,\}' \
  ~/.codeg ~/.config ~/.claude ~/.codex ~/.openclaw ~/.pi /etc /opt 2>/dev/null
```

已知的两种形态（别混）：

| 形态 | 网关 | 权威 key 文件 |
| --- | --- | --- |
| Linux 服务器 | LiteLLM `:4000` + commandcode-proxy `:8898` | `/etc/commandcode-proxy.env` |
| Mac | codeg 自建 python 代理 `:15825`（+ 用户自己的 cc-switch `:15721`） | `~/.codeg/commandcode-goat-key`；deploy 脚本另用 `~/.config/codeg/opencode-go.env` |

> ⚠️ **Mac 上 `~/.claude/settings.json` 和 `~/.codex/config.toml` 归 cc-switch 管**，
> 不要直接改这两个文件；codeg 侧只改 `~/.codeg/` 和各 agent 自己的配置。

## 第 2 步：换 key（先改源头，再对齐产物）

`ccg` 的 key 从来不只有一处。分三类处理：

**① 源头（手改，只有它需要你动手）**

| 平台 | 文件 |
| --- | --- |
| Linux | `/etc/commandcode-proxy.env` 的 `COMMANDCODE_API_KEY=` |
| Mac | `~/.codeg/commandcode-goat-key`（权限 600） |
| 其他 | 凡是第 1 步 `grep` 出来的、被代理进程读取的那个 env/凭据文件 |

**② 脚本会重新生成的产物**（改完源头后跑生成器即可，别手改）

`/opt/litellm/config.yaml`（每个 `ccg/*` 一条，几十条）、`~/.hermes/config.yaml`、
`~/.config/opencode/opencode.jsonc`、`~/.openclaw/openclaw.json`、`~/.kimi-code/config.toml`、
`~/.pi/agent/{auth,models}.json`、codex 的 model catalog。

生成器：`refresh_models.py`（服务器在 `/root/codeg-work/`，仓库在 `tools/`）。
**注意：巡检/刷新实际跑的是部署副本，不是仓库副本，改完要同步过去。**

**③ 脚本不管、最容易漏的凭据库**（必须手改，否则「一半好一半 401」）

| 文件 | 位置 |
| --- | --- |
| `~/.codex/config.toml` | `experimental_bearer_token = "<key>"`（codex 直连 CC 用） |
| `~/.openclaw/state/openclaw.sqlite` | 表 `config_machine_state`，`state_key='authProfiles.store'` 的 JSON 里 `ccg:default.key` —— **openclaw 真正生效的凭据在这里，只改 openclaw.json 没用** |

用脚本改这两处（sqlite 别手敲 SQL）：

```bash
python3 - <<'PY'
import json, re, sqlite3, os
NEW = open(os.path.expanduser('~/.codeg/commandcode-goat-key')).read().strip() \
      if os.path.exists(os.path.expanduser('~/.codeg/commandcode-goat-key')) \
      else '<NEW_KEY>'
# codex
p = os.path.expanduser('~/.codex/config.toml')
if os.path.exists(p):
    t = open(p).read()
    t2, n = re.subn(r'(experimental_bearer_token\s*=\s*")[^"]+(")',
                    lambda m: m.group(1) + NEW + m.group(2), t)
    open(p, 'w').write(t2); print('codex bearer 对齐', n, '处')
# openclaw state db
p = os.path.expanduser('~/.openclaw/state/openclaw.sqlite')
if os.path.exists(p):
    c = sqlite3.connect(p)
    row = c.execute("select value_json from config_machine_state "
                    "where state_key='authProfiles.store'").fetchone()
    if row:
        d = json.loads(row[0]); hit = 0
        for name, prof in d.get('profiles', {}).items():
            if name.startswith('ccg') and prof.get('key') != NEW:
                prof['key'] = NEW; hit += 1
        if hit:
            c.execute("update config_machine_state set value_json=? "
                      "where state_key='authProfiles.store'",
                      (json.dumps(d, ensure_ascii=False),))
            c.commit()
        print('openclaw authProfiles 对齐', hit, '处')
    c.close()
PY
```

**④ 生成物里带真 key 的分发包**（换 key 后要重新生成或同步，否则发出去的包全是死 key）

Windows kit（`*-with-keys.md` / `COMPACT.md`）、Mac kit（`mac-out/*`）、
以及任何挂在 web 目录里供下载的版本（例：`/var/www/dl/<hash>.md`）。

## 第 3 步：重启

```bash
# Linux
systemctl restart commandcode-proxy litellm   # 名字按第 1 步实际查到的来
# Mac（launchd）
launchctl bootout gui/$(id -u)/app.codeg.opencode-go-proxy
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/app.codeg.opencode-go-proxy.plist
# 若 agent 的配置是 DB/进程内缓存（codeg 的 agent_setting）
systemctl restart codeg     # 会杀掉正在跑的会话，挑没人的时候
```

## 第 4 步：复验（三种端点都要打，别只打一个）

```bash
for m in <本机 ccg 清单里的 3-5 个>; do
  echo -n "$m "
  curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:<网关端口>/v1/chat/completions \
    -H 'content-type: application/json' \
    -d "{\"model\":\"$m\",\"max_tokens\":64,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"
done
```

- chat agent → `/chat/completions`
- codex → `/responses`（`wire_api = "responses"`；不是所有 ccg 模型都在这个端点，
  报 `not supported on this endpoint` 是模型不合端点，不是 key 错）
- Claude Code → Anthropic 协议 `/v1/messages`（经 LiteLLM 或 commandcode-proxy）

已知的假失败（别去追）：

- `max_tokens` / `max_output_tokens` 给小（如 4）会被 `gpt-5.6-*` / `gpt-6-*` 判非法 → 用 64 以上
- 模型清单里 `/models` 的差集只能当参考，账号权限差异要看真打的结果

## 第 5 步：收尾与报告

```bash
# 活配置里不允许残留非当前 key 的令牌
grep -rl --binary-files=text 'user_[A-Za-z0-9]\{40,\}' \
  /etc/commandcode-proxy.env /opt/litellm/config.yaml ~/.hermes/config.yaml \
  ~/.codex/config.toml ~/.pi/agent 2>/dev/null | while read f; do
  echo "$f: $(grep -o 'user_[A-Za-z0-9]\{40,\}' "$f" | sort -u | sed 's/\(user_....\).*/\1…/')"
done
```

报告里必须给：① 定性的那条 curl 的 HTTP 码；② 本机 key 的落点清单（改了几处、哪几处是脚本不管的）；
③ 复验的模型 × 端点 × HTTP 码；④ 还没解决的部分和原因。

**别把真 key 写进任何会提交进 git 的文件或聊天回复的主体里**，仓库一律用
`${COMMANDCODE_API_KEY}` 占位符。

## 第 6 步：每周模型巡检（这类机器基本都有，不处理的话修复只活到下周）

先把「本机到底有没有巡检、它跑的是谁」查清楚：

```bash
# a) codeg 自动化（气泡：prompt 存在 sqlite 里）
python3 - <<'PY'
import json, os, sqlite3
p = os.path.expanduser('~/.local/share/codeg/codeg.db')
if os.path.exists(p):
    c = sqlite3.connect(p)
    for aid, name, en, cron, cfg in c.execute(
            'select id,name,enabled,cron,config from automation'):
        if not en: continue
        txt = ''.join(b.get('text', '') for b in json.loads(cfg or '{}').get('prompt_blocks', []))
        hit = ('COMMANDCODE' in txt) or ('refresh_models' in txt) or ('模型巡检' in txt)
        print(f'#{aid} {name} cron={cron} 相关={hit} 硬编码key={bool(__import__("re").search(r"user_\\w{30,}", txt))}')
PY

# b) 系统级调度
crontab -l 2>/dev/null | grep -Ei 'model|refresh|codeg'
ls /etc/cron.d/ 2>/dev/null
systemctl list-timers --all 2>/dev/null | grep -Ei 'model|refresh|codeg'
launchctl list 2>/dev/null | grep -i codeg        # macOS
grep -l . ~/Library/LaunchAgents/*codeg* 2>/dev/null
```

要做的两件事：

1. **巡检提示词里如果硬编码了 key**（上面 `硬编码key=True`）→ 改成从权威 key 文件读：
   `CCKEY=$(grep -oP 'COMMANDCODE_API_KEY=\K\S+' <权威key文件>)`。像服务器那样已经是 grep 读的，就不用动。
2. **巡检跑的是部署副本，不是仓库副本**（服务器是 `/root/codeg-work/refresh_models.py`，
   Mac 通常在 `~/.codeg/` 下）。把 `tools/refresh-models.py` 最新版同步过去，因为它末尾第 10 步会
   顺手对齐 codex 的 `experimental_bearer_token`、openclaw 的 `authProfiles.store`，并做 key 自检。
   不同步 = 下周换 key 时同样的坑再踩一遍。

验证（load 低时跑，会重拉上游清单）：

```bash
python3 <部署副本路径>
# 期望末尾出现：✓ Command Code key 自检：N 个活配置全部为当前 key
```

补充：如果巡检是用 `pi` 起的会话，pi 自己的 `~/.pi/agent/models.json` / `auth.json` 里也有 ccg key，
属于第 2 步②的产物，不要漏。最后确认下一次运行时间（`automation.next_run_at` 或
`systemctl list-timers`），确保它会在你修好之后真的跑一次。
