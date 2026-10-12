# PROMPT-ONBOARD：在新机器上配置 codeg 的 agent 与模型

你是这台机器上的工程 agent。任务：把 codeg 配置成「多供应商 + 统一前缀」的形态，
并让各 agent 的模型清单反映**这台机器自己的**账号权限。

配置仓库：`https://github.com/gyc0109/codeg-config`

---

## 0. 先盘点，不要先动手

跑一遍下面这些，**把结果完整贴给我**，然后停下来等我确认：

```bash
# codeg 装在哪、DB 在哪、在不在跑
ls -d /Applications/codeg.app ~/Library/Application\ Support/app.codeg 2>/dev/null
ps aux | grep -i codeg | grep -v grep
# Linux: systemctl is-active codeg; ls /usr/local/share/codeg

# DB 位置（macOS 和 Linux 不同，且可能有多个，选行数非 0 的那个）
DB=~/Library/Application\ Support/app.codeg/codeg.db      # macOS
DB=/root/.local/share/codeg/codeg.db                       # Linux
sqlite3 "$DB" "SELECT COUNT(*) FROM agent_setting;"
sqlite3 "$DB" "SELECT agent_type, installed_version FROM agent_setting ORDER BY sort_order;"
sqlite3 "$DB" "SELECT id, agent_type, name, substr(model,1,60) FROM model_provider ORDER BY id;"

# 本机有哪些代理在监听（关键：可能已经有别的代理了）
lsof -nP -iTCP -sTCP:LISTEN | grep -iE 'codeg|litellm|proxy|switch|python|node'

# 各 agent 配置是否存在
for f in .claude/settings.json .codex/config.toml .pi/agent/models.json \
         .kimi-code/config.toml .hermes/config.yaml .config/opencode/opencode.jsonc \
         .codebuddy/models.json .openclaw/openclaw.json .dsh/settings.yaml; do
  [ -f "$HOME/$f" ] && echo "OK $f" || echo "-- $f"
done

# 供应商 key 有没有
ls -la ~/.codeg/*key* /etc/*key* 2>/dev/null
```

**必问我的三件事：**
1. 这台机器上是否已经跑着别的代理（比如 cc-switch）？如果有，**哪些 agent 归它管**？
   归它管的配置文件一律不要动。
2. 四个供应商（OpenCode Go / Command Code / DeepSeek 官方 / 火山方舟）的 key 分别是？
3. codeg 里哪些 agent 需要配？

---

## 1. 架构（目标形态）

**统一前缀，四家供应商：**

| 前缀 | 供应商 | 上游 |
| --- | --- | --- |
| `ocg/` | OpenCode Go | `https://opencode.ai/zen/go/v1` |
| `ccg/` | Command Code GOAT | `https://api.commandcode.ai/provider/v1` |
| `ds/` | DeepSeek 官方 | `https://api.deepseek.com/v1` |
| `ark/` | 火山方舟 / 豆包 | `https://ark.cn-beijing.volces.com/api/v3` |

前缀是**别名**，转发前要剥掉（`ocg/xxx` → 上游收 `xxx`）。

**两种落地方式，按机器情况选：**

### 方式 A：只有一个本地代理（推荐，改动小）

仓库里的 `install/opencode-go-proxy`（Linux）或 `mac/opencode-go-proxy.py`（macOS）
就是这种：单端口、按前缀分流到 4 个上游。

需要额外处理：
- **OCG 必须注入 session header**（`x-opencode-session`），否则拒绝请求。
  大多数 agent 不会发，所以由代理补一个 uuid。
- **CC 的 `/messages` 不接受 messages 数组里的 `role: "system"`**，
  要把它提到顶层 `system` 字段，否则 `400 Invalid input at messages.N.role`。
- **ds/ 和 ark/ 拒绝 `role: "developer"`**，要改写成 `system`，否则 422。

### 方式 B：LiteLLM + 代理（服务器用的）

仓库 `install/litellm/config.yaml`。额外注意：
- `ocg/` 那一组必须是 **chat ∪ responses 的并集**（cline/code_buddy/grok/deepseek
  走 chat 端点，codex 走 responses）。
- `additional_drop_params` 的 YAML 锚点 `&id001` **只能在第一条定义**，
  其余用 `*id001`。重复定义报 `found duplicate anchor`；把别名后面接上序列项会报
  `expected <block end>`。改完一定 `yaml.safe_load` 验一遍。

---

## 2. key 的存放

**环境变量优先，其次读文件。** 文件一律 600 权限。

```
~/.codeg/opencode-go-key           # OPENCODE_API_KEY
~/.codeg/commandcode-goat-key      # COMMANDCODE_API_KEY
~/.codeg/deepseek-key              # DEEPSEEK_API_KEY
~/.codeg/ark-key                   # VOLCENGINE_ARK_KEY
```

Linux 服务器上用的是 `/etc/opencode-go-proxy.env`、`/etc/deepseek-official-key`、
`/etc/volcengine-ark-key`，systemd `EnvironmentFile` 注入。

⚠️ **绝对不要把真实 key 写进仓库**，写 `${...}` 占位符。

---

## 3. ⚠️ 最关键的一条：模型清单必须在本机实测

**每台机器的供应商 key 可能属于不同账号，套餐权限不同。**

实测例证（2026-10-11）：同一个 Command Code GOAT 供应商，两台机器：

| | 机器 A | 机器 B |
| --- | --- | --- |
| chat 可用 | 54 | **50** |
| responses 可用 | 47 | **44** |

机器 B 少了 6 个（`Qwen3.6-Max-Preview` 报 404、`gemini-3.7-flash` 和
`muse-spark-*` 报 403），多了 2 个（`laguna-s-2.1-free`、`mimo-v2.5`）。

**所以：不要照抄仓库里 `config/` 下的模型清单，必须用本机 key 重新探测。**
照抄的后果是 agent 列表里出现一堆选中就报错的模型。

---

## 4. 探测流程

### 4.1 OCG

`GET https://opencode.ai/zen/go/v1/models`（**只返回 id，不带上下文窗口**）。
上下文要从 opencode 的 `~/.cache/opencode/models.json` 里 provider `opencode-go` 取。

对每个模型分别打 `/chat/completions` 和 `/responses`，记录哪些可用。

### 4.2 CC

`GET https://api.commandcode.ai/provider/v1/models` 的每一项都带
**`supported_endpoints`**，这是协议判定的权威依据：

| `supported_endpoints` | 含义 |
| --- | --- |
| `['/chat/completions','/responses']` | 两类 agent 都能用 |
| `['/chat/completions']` | 只有 chat |
| `['/messages']` | 只有 Claude 协议 |

再逐个打 `/chat/completions` 判套餐（`MODEL_NOT_IN_PLAN` = 套餐外；
`No available providers match` = 上游挂了；`Model not exist` / 认证失败 = 本机账号无权限）。

得到两个集合：
- `chat_ok` = (both ∪ chat_only) − 套餐外 − 不可用
- `resp_ok` = both − 套餐外 − 不可用

> 💡 `resp_ok` 是 `chat_ok` 的子集，**给 codex 之类的用 resp_ok**，
> 否则会拿到 responses-only 的模型去调 chat，报
> `Model does not support this protocol`。

### 4.3 ds / ark

DeepSeek 2 个、Ark 14 个，量小，直接打。

⚠️ **Ark 的模型名必须带日期后缀**（`doubao-seed-2-1-pro-260915`）。
短名 `doubao-seed-2-1-pro` 会被上游 400 `Invalid model name`。

⚠️ Ark 那一大堆 `Shutdown` / `Retiring` 状态的模型**不要选**。

---

## 5. 各 agent 怎么接

模型名字前缀保持一致，但每个 agent 的"别名层"实现不同：

| Agent | 机制 |
| --- | --- |
| `pi` | `~/.pi/agent/models.json` 里定义 provider `ocg`/`ccg`/`ds`/`ark`（`models` 必须是**数组**） |
| `opencode` | `~/.config/opencode/opencode.jsonc` 的 `provider.<id>.models`，另加 `disabled_providers:["opencode-go"]` |
| `kimi_code` | `~/.kimi-code/config.toml`，模型段自带 `model` 字段 |
| `hermes` | `~/.hermes/config.yaml` 的 `custom_providers`，靠 **name 转 slug** |
| `code_buddy` | `~/.codebuddy/models.json` + env `CODEBUDDY_*` |
| `open_claw` | `~/.openclaw/openclaw.json` 的 `models.providers` + allowlist |
| `cline` | 见下面第 6 节的坑 |
| `codex` | `codeg-model-catalog.json`（**codex 只支持 responses**）|
| `claude_code` | provider 的 `model` 是 JSON，按角色分槽位 |

---

## 6. 必须知道的一堆坑

### cline（最容易踩，能让人以为"配好了"）

两个独立问题：

1. **环境变量是 `CLINE_PROVIDER` / `CLINE_BASE_URL` / `CLINE_API_KEY` / `CLINE_MODEL`**，
   不是 `OPENAI_*`。用错会退回官方 Cline 账号，报
   `Unauthorized: ... re-authenticate your Cline account`。
2. **cline 的可选模型不读 `providers.json`**，而是同目录的 `models.json`。
   缺了就只有 `gpt-4o` 一个选项，一请求就
   `Invalid model name passed in model=gpt-4o`。

   ```json
   {"version":1,"providers":{"openai-compatible":{
     "provider":{"name":"...","baseUrl":"...","defaultModelId":"ocg/..."},
     "models":{"ocg/xxx":{...}},
     "discoveredModelIds":["ocg/xxx"]}}}
   ```

### open_claw

1. **`agents.entries` 必须非空**（`{"main": {}}`），否则网关起不来。
   `openclaw doctor --fix` 修。
2. doctor 会把 `agents.defaults.models` 迁移成 **`agents.defaults.modelPolicy.allow`**，
   **之后改 allowlist 要改 `modelPolicy.allow`**，改 `models` 不生效。

### pi

`pi-acp` 只是 ACP 适配器，**还需要主程序 `pi`**（`npm i -g @earendil-works/pi-coding-agent`），
否则 `session/new` 报 `Could not start pi: executable not found`。

另外 `~/.pi/agent/settings.json` 的 `defaultProvider`/`defaultModel` 要一起改，
不然会静默回退到列表第一个模型。

### kimi

- `default_model` 必须在**文件顶部**，放在某个 `[models."..."]` 段之后就变成那个段的键了。
- **每个 `[providers.*]` 段里还各有一个 `default_model`**，容易漏。

### 其他

- **macOS 没有 `timeout`**，用 perl 版或 `gtimeout`。
- **macOS 的 BSD sed 不认替换里的 `\n`**。
- **Mac 的 node 常在 fnm 里**（`~/.local/share/fnm/node-versions/*/installation/bin`），
  非交互 shell 的 PATH 里没有。
- **系统 python 没 pyyaml 且 PEP 668 挡住 pip**，建个 venv。
- **备份别都用同一个文件名**（`config.yaml` 在 hermes 和 litellm 下同名，会互相覆盖）。
- **别开太高的并发去探测**：几十个请求并发 + 网关重启能把这台机器 load 干到 30+，
  把网关压崩，然后你会得到一堆假失败。

---

## 7. 验证（不验证不算做完）

**不能只看配置文件。** 每个 agent 都要发一条真实请求：

```bash
# 通用：要求模型原样回一个 token
PROMPT="Reply with exactly: PONG"
```

- 有 CLI 的（kimi / hermes / grok / codebuddy / openclaw / opencode run）直接跑
- **ACP-only 的（pi / claude_code / cline / codex）走 ACP 协议测**：
  `initialize` → `session/new` → `session/prompt`，收 `agent_message_chunk`。
  这跟 codeg 走的是同一条路，最权威。
- 模型层面：把该机器可用清单里的**每一个**模型都打一遍，列 OK/FAIL。

最后把 **agent 通过数 + 模型通过数 + 失败清单**一起报给我。

---

## 8. 汇报格式

```
## 现状
<盘点结果>

## 改动
<每条：文件 → 改了什么 → 为什么>

## 验证
agent:  11/11 通过（列出）
模型:   95/96 通过
失败:   <逐条，附原因。是上游限流/套餐外 还是 配置问题？>

## 备份位置
<路径>

## 我不确定 / 需要你决定的
<列出来>
```

**遇到不确定的先问我，不要自己猜着改。**
