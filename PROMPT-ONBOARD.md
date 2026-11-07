# PROMPT-ONBOARD：在新机器上配置 codeg 的模型与 agent

> v2 · 2026-11-07 · 对齐生产机（Tencent Seoul，Debian 13）的实际形态
> 给「另一台机器上的 AI」看的交接说明。读完先盘点，不要直接动手。

你是这台机器上的工程 agent。任务：把 codeg 配成「四供应商统一前缀 + 多 agent」的形态，
并让模型清单反映**这台机器自己的**账号权限。

配置仓库（公开）：`https://github.com/gyc0109/codeg-config`
密钥包：由人单独传给你（`model-keys-20261107.tar.gz`，600 权限），**不要写进仓库、不要落到日志里**。

---

## 0. 铁律

1. **先盘点，贴结果，等人确认再改。**
2. **密钥只以环境变量或 600 权限文件形式存在**；仓库里只能出现 `${VAR}` 占位符。
3. 这台机器上如果已经跑着别的代理（cc-switch 之类），**归它管的配置文件一律不动**，
   先在盘点里标出来问人。
4. 模型清单**必须本机实测**（见 §5），不要照抄仓库 `config/` 下的清单。
5. 不确定就问，不要猜着改。

---

## 1. 盘点（原样贴回结果）

```bash
# codeg 装在哪、在不在跑
systemctl is-active codeg; ls -d /usr/local/share/codeg 2>/dev/null
# macOS: ls -d /Applications/codeg.app ~/Library/Application\ Support/app.codeg

# DB 位置（可能有多份，选 agent_setting 行数非 0 的那个）
DB=/root/.local/share/codeg/codeg.db           # Linux
# DB=~/Library/Application\ Support/app.codeg/codeg.db   # macOS
sqlite3 "$DB" "SELECT COUNT(*) FROM agent_setting;"
sqlite3 "$DB" "SELECT agent_type, installed_version, model_provider_id FROM agent_setting ORDER BY sort_order;"
sqlite3 "$DB" "SELECT id, name, agent_type, api_url, substr(model,1,40) FROM model_provider ORDER BY id;"

# 谁在监听（关键：可能已经有代理占着端口）
ss -lntp | grep -E ':(4000|8896|8897|8898|8899)\b'
systemctl list-units --type=service --state=running | grep -Ei 'codeg|litellm|proxy'

# 密钥文件在不在（只看有没有，别打印内容）
ls -l /etc/opencode-go-proxy.env /etc/commandcode-proxy.env \
      /etc/deepseek-official-key /etc/volcengine-ark-key ~/.codeg/*key* 2>/dev/null

# 已装 agent（npm 全局 + codeg 自管 binary）
npm ls -g --depth=0 2>/dev/null
ls ~/.local/share/codeg/acp-binaries/ 2>/dev/null
```

**必须问人的四件事：**

1. 这台机器上是否已有别的代理在跑？哪些 agent 归它管？
2. 四个供应商（OpenCode Go / Command Code / DeepSeek 官方 / 火山方舟）分别用哪个 key
   —— 是否就是密钥包里那套，还是这台机器另有账号？
3. codeg 里哪些 agent 需要配（全配，还是只配常用的几个）？
4. codeg 的 Web 端口要不要对外？（默认必须只监听 loopback，见 §8）

---

## 2. 目标架构

```
codeg ──┬─ http://127.0.0.1:4000      → litellm（协议桥 + 105 个模型）
        │                                 ├─ ocg/*  → :8899 opencode-go-proxy
        │                                 └─ ccg/*  → https://api.commandcode.ai
        ├─ http://127.0.0.1:8896/v1   → opencode-go-proxy 的 ds 口 → api.deepseek.com
        └─ http://127.0.0.1:8897/v1   → opencode-go-proxy 的 ark 口 → ark.cn-beijing.volces.com
```

**四家前缀**（前缀是别名，转发前剥掉）：

| 前缀 | 供应商 | 上游 | 模型数 |
| --- | --- | --- | --- |
| `ocg/` | OpenCode Go | `https://opencode.ai/zen/go` | 29 |
| `ccg/` | Command Code GOAT | `https://api.commandcode.ai/provider/v1` | 61 |
| `ds/` | DeepSeek 官方 | `https://api.deepseek.com/v1` | 2 |
| `ark/` | 火山方舟 | `https://ark.cn-beijing.volces.com/api/v3` | 14 |

### 三个进程，各管一件事

| 进程 | 端口 | 干什么 | 源码 |
| --- | --- | --- | --- |
| `litellm` | **4000** | Anthropic↔OpenAI 协议互转；暴露全部 `ocg/ ccg/ ds/ ark/` 模型名 | `install/litellm/config.yaml` |
| `opencode-go-proxy` | **8899**(ocg) / **8896**(ds) / **8897**(ark) | 剥前缀、给 OCG 注入 `x-opencode-session`、把 `role:developer` 改写成 `system` | `install/opencode-go-proxy` |
| `commandcode-proxy` | **8898** | 把 messages 数组里的 `role:"system"` 提到顶层 `system` 字段，专供 Claude Code 走 CCG | `install/commandcode-proxy` |

> 8898 已被 commandcode-proxy 占用，所以 DeepSeek 用 **8896**，不是 8898。
> 端口全部 `127.0.0.1`，不对外。

**只有一台机器、且不需要 Anthropic 协议时**，可以只跑 `opencode-go-proxy`，
把各 agent 的 base_url 直接指向 8896/8897/8899（见 §3 的端口表）。这是改动最小的做法。

### 代理层必须处理的三个上游怪癖

- **OCG 必须带 session header**（`x-opencode-session`），否则拒绝请求；大多数 agent 不发，由代理补 uuid。
- **CCG 的 `/messages` 不接受 messages 数组里的 `role:"system"`**，要提到顶层 `system`，
  否则 `400 Invalid input at messages.N.role`。
- **ds / ark 拒绝 `role:"developer"`**，要改写成 `system`，否则 422。

### LiteLLM 配置的两条硬约束

- `ocg/` 那一组必须是 **chat ∪ responses 的并集**（cline/code_buddy/grok/deepseek 走 chat，
  codex 走 responses）。
- `additional_drop_params` 的 YAML 锚点 `&id001` **只能在第一条定义**，其余写 `*id001`。
  重复定义报 `found duplicate anchor`；别名后接序列项报 `expected <block end>`。
  改完必须 `python3 -c "import yaml,sys;yaml.safe_load(open(sys.argv[1]))"` 验一遍。

---

## 3. codeg 侧怎么配（就是两个表）

codeg 的模型配置**全在 DB 里**，没有配置文件。

### 3.1 `model_provider`：一行 = 一个「供应商 × agent 类型」

同一家供应商要为每个 agent 各建一行，因为 `agent_type` 和 `api_url` 形态不同。

| 列 | 填法 |
| --- | --- |
| `name` | 带前缀的显示名，如 `OpenCode Go (ocg/)`、`Command Code GOAT (ccg/)` |
| `agent_type` | 该行服务的 agent，如 `claude_code` / `kimi_code` / `grok` / `deepseek` |
| `agent_types_json` | `["<同上>"]` |
| `api_url` | OpenAI 风格 agent → `http://127.0.0.1:4000/v1`；`claude_code` → `http://127.0.0.1:4000`（**不带 /v1**）；ds/ark 的 OpenAI 风格 agent 可直连 `:8896/v1`、`:8897/v1` |
| `api_key` | **填占位符 `local`** —— 真 key 在代理层，这里不用真 key |
| `model` | 普通 agent：单个模型 id（如 `ocg/beam-free`）；`claude_code`：JSON 槽位 |

`claude_code` 的 `model` 必须是 JSON，按角色分槽：

```json
{"main": "ocg/glm-5.3-flash", "reasoning": "ocg/glm-5.3-flash", "haiku": "ocg/deepseek-v4.1-flash"}
```

生产机上共 **16 行** = 4 家供应商 × 4 个 agent 类型
（`claude_code / kimi_code / grok / deepseek`）。

### 3.2 `agent_setting`：每个 agent 一行

| 列 | 说明 |
| --- | --- |
| `agent_type` | **存的是带 JSON 引号的字符串**，如 `"command_code"`。写库时别漏引号 |
| `env_json` | 该 agent 启动时注入的环境变量（JSON 对象） |
| `model_provider_id` | 绑定到 §3.1 的某一行 |
| `installed_version` | **只在 codeg 自己安装时写入**，走 npm 升级不会更新，见 §7.6 |

各 agent 的 `env_json` 变量名（照抄，别自创）：

| agent | 变量 |
| --- | --- |
| `claude_code` | `ANTHROPIC_AUTH_TOKEN` `ANTHROPIC_BASE_URL` `ANTHROPIC_MODEL` `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL` `ANTHROPIC_CUSTOM_MODEL_OPTION`(+`_NAME` `_DESCRIPTION`) |
| `codex` | `OPENAI_BASE_URL` `OPENAI_MODEL` `OPENCODE_GO_KEY` |
| `cline` | `CLINE_PROVIDER`(= `openai-compatible`) `CLINE_BASE_URL` `CLINE_API_KEY` `CLINE_MODEL` |
| `kimi_code` | `KIMI_MODEL_BASE_URL` `KIMI_MODEL_API_KEY` `KIMI_MODEL_NAME` |
| `grok` | `GROK_XAI_API_BASE_URL` `XAI_API_KEY` `GROK_DEFAULT_MODEL` `OPENAI_MODEL` |
| `deepseek` | `DEEPSEEK_BASE_URL` `DEEPSEEK_API_KEY` `DEEPSEEK_ACP_PROVIDER` `DEEPSEEK_ACP_MODEL` |
| `code_buddy` | `CODEBUDDY_BASE_URL` `CODEBUDDY_API_KEY` `CODEBUDDY_MODEL` `CODEBUDDY_DISABLE_BUILTIN_MODELS=1` |
| `hermes` | `HERMES_INFERENCE_PROVIDER`(= `custom:ocg-beam-free`) `HERMES_INFERENCE_MODEL` |
| `antigravity` | `AGY_LLM_GATEWAY_URL` |
| `command_code` | `COMMAND_CODE_API_KEY`（这个要**真 key**，它不经过本地代理） |

> 占位符 agent（`pi` / `open_code` / `open_claw` / `gemini` / `cursor` / `qoder` /
> `kiro` / `zcode` / `trae` / `minimax_code`）的 env_json 为空，配置在各自的家目录文件里。

### 3.3 写库规矩

- 改库前先停 codeg（`systemctl stop codeg`），改完再起，避免被内存态覆盖。
- 先备份：`sqlite3 "$DB" ".backup /root/codeg-$(date +%F).db"`。
- `agent_type` 的值带引号，`WHERE agent_type='\"cline\"'` 这样查。

---

## 4. key 怎么放

**环境变量优先，其次读文件，文件一律 600。**

| 变量 | 生产机位置 |
| --- | --- |
| `OPENCODE_GO_API_KEY` | `/etc/opencode-go-proxy.env`（systemd `EnvironmentFile`） |
| `COMMANDCODE_API_KEY` | `/etc/commandcode-proxy.env`，另内联在 `/opt/litellm/config.yaml` 的 `ccg/*` 条目 |
| `DEEPSEEK_OFFICIAL_API_KEY` | `/etc/deepseek-official-key` |
| `VOLCENGINE_ARK_API_KEY` | `/etc/volcengine-ark-key` |

便携机也可以用 `~/.codeg/{opencode-go,commandcode-goat,deepseek,ark}-key`（代理会自动回退读这些文件）。

⚠️ **绝对不要把真实 key 写进仓库**，仓库里只有 `.example` 模板。

---

## 5. ⚠️ 模型清单必须本机实测

每台机器的 key 可能属于不同账号，套餐权限不同。实测例证（2026-10-11）：

| | 机器 A | 机器 B |
| --- | --- | --- |
| CCG chat 可用 | 54 | **50** |
| CCG responses 可用 | 47 | **44** |

机器 B 少 6 个（404 / 403），多 2 个。**照抄清单的后果是 agent 列表里一堆选中就报错的模型。**

### 5.1 OCG

`GET https://opencode.ai/zen/go/v1/models`（只返回 id，不带上下文窗口）；
上下文窗口从 `~/.cache/opencode/models.json` 的 provider `opencode-go` 取。
每个模型分别打 `/chat/completions` 和 `/responses`。

### 5.2 CCG

`GET https://api.commandcode.ai/provider/v1/models`，每项带 **`supported_endpoints`**，这是协议判定的权威依据：

| `supported_endpoints` | 含义 |
| --- | --- |
| `['/chat/completions','/responses']` | 两类 agent 都能用 |
| `['/chat/completions']` | 只有 chat |
| `['/messages']` | 只有 Claude 协议 |

再逐个打 `/chat/completions` 判套餐：
`MODEL_NOT_IN_PLAN` = 套餐外；`No available providers match` = 上游挂了；`Model not exist` = 无权限。

- `chat_ok` = (both ∪ chat_only) − 套餐外 − 不可用
- `resp_ok` = both − 套餐外 − 不可用 ← **给 codex 用，否则 `Model does not support this protocol`**

### 5.3 ds / ark

量小直接打。**Ark 模型名必须带日期后缀**（`doubao-seed-2-1-pro-260915`），
短名报 `400 Invalid model name`；`Shutdown`/`Retiring` 状态的一律不要。

> 别开高并发：几十个并发请求 + 网关重启能把机器 load 干到 30+，然后你会得到一堆假失败。

---

## 6. 各 agent 的别名层

| Agent | 机制 |
| --- | --- |
| `pi` | `~/.pi/agent/models.json` 定义 provider `ocg/ccg/ds/ark`（`models` 必须是**数组**）；`settings.json` 的 `defaultProvider`/`defaultModel` 一起改 |
| `open_code` | `~/.config/opencode/opencode.jsonc` 的 `provider.<id>.models`，另加 `disabled_providers:["opencode-go"]` |
| `kimi_code` | `~/.kimi-code/config.toml`；`default_model` 必须在**文件顶部**，且每个 `[providers.*]` 段里还各有一个 |
| `hermes` | `~/.hermes/config.yaml` 的 `custom_providers`，靠 name 转 slug |
| `code_buddy` | `~/.codebuddy/models.json` + env `CODEBUDDY_*` |
| `open_claw` | `~/.openclaw/openclaw.json` 的 `models.providers` + allowlist |
| `cline` | 见 §7.1 |
| `codex` | `codeg-model-catalog.json`（**只支持 responses**） |
| `claude_code` | provider 的 `model` 是 JSON 槽位 |

---

## 7. 必须知道的坑

### 7.1 cline（最容易踩，能让人以为"配好了"）

1. 环境变量是 `CLINE_PROVIDER` / `CLINE_BASE_URL` / `CLINE_API_KEY` / `CLINE_MODEL`，
   **不是 `OPENAI_*`**。用错会退回官方 Cline 账号，报 `re-authenticate your Cline account`。
2. **可选模型不读 `providers.json`，读同目录的 `models.json`**。缺了只剩 `gpt-4o`，
   一请求就 `Invalid model name passed in model=gpt-4o`。

### 7.2 open_claw

1. `agents.entries` 必须非空（`{"main": {}}`），否则网关起不来。
2. doctor 会把 `agents.defaults.models` 迁移成 **`modelPolicy.allow`**，之后改 allowlist 要改那里。
3. 版本跨越可能触发 SQLite schema 迁移，报 `sqlite uses schema version N ... run openclaw doctor --fix`。
   **跑之前先 `tar czf` 备份 `~/.openclaw`。**
4. 它是 ACP 桥 + **systemd user 服务** `openclaw-gateway`（端口 18789）；
   查询要 `XDG_RUNTIME_DIR=/run/user/0 systemctl --user ...`。网关没起来时 ACP 会**静默 exit 0**。

### 7.3 pi

`pi-acp` 只是适配器，还需要主程序 `pi`（`npm i -g @earendil-works/pi-coding-agent`），
否则 `session/new` 报 `Could not start pi: executable not found`。
`pi-acp` 重装后 `/usr/local/bin/pi-acp-provider-label-patch` 的补丁会被覆盖，
要重跑（也挂在 `codeg.service` 的 `ExecStartPre` 里）。
`pi-acp 0.0.34` 只验证过 `pi-coding-agent 0.86.x`，**不要擅自把 pi 升到 1.x**。

### 7.4 安装层：npm 全局包与软链

- npm 全局包在 `/usr/lib/node_modules`，可执行文件软链在 `/usr/bin`。
  迁移机器时**两者必须一起搬**；只搬包不搬软链，codeg 会报 `INSTALLED=no`，
  修法是 `npm i -g <包名>` 重跑一遍。
- 装在 `~/.local/bin` 的东西 **codeg 看不见**（systemd 用默认 PATH，不含 `~/.local/bin`），
  要在 `/usr/local/bin` 补软链。
- **codeg 自带的 agent registry 是打包时的旧快照**，照它的命令装会降级
  （曾把 open_claw 降回 2026.9.8）。**以 `npm view <pkg> version` 为准。**
- npm 11 有 allow-scripts 门禁，postinstall 会被**静默跳过**；需要编译的包要
  `npm i -g <pkg> --allow-scripts=<pkg>`（如 `@minimax-ai/code` 依赖 `better-sqlite3`）。

### 7.5 codeg 自管 binary（cursor / open_code / antigravity）

装在 `~/.local/share/codeg/acp-binaries/<agent>/<version>/`。
升级后**旧版本目录不一定会自动删**（cursor 有过 558M 残留），要手动清。

### 7.6 `installed_version` 会过期

走 npm 升级后，DB 里 `agent_setting.installed_version` 仍是旧值，UI 会一直显示"可升级"。
以 `npm ls -g --json` 为准，手动回写这一列。
（这一列只影响显示和 preflight 比对，`INSTALLED=yes/no` 是实时探测的，不受影响。）

### 7.7 zcode 是两层

`zcode-acp-server`（ACP 桥）+ 官方 ZCode 客户端 `zcode.cjs`（后端）。
只装前者，preflight 会报 `Official ZCode CLI could not be found`。
桥靠 `ZCODE_BIN` → PATH 的 `zcode` → `/opt/ZCode/resources/glm/zcode.cjs` 顺序找；
官方 CLI 还需要 `ZCODE_BUILTIN_PROVIDER_CONFIG_FILE` 和 `ZCODE_PERSONAL_PROVIDER_CONFIG_FILE`
两个环境变量，否则 `无法定位 CLI ZCode Built-in Provider Config`。

### 7.8 平台差异（macOS）

- 没有 `timeout`（用 perl 版或 `gtimeout`）；BSD sed 不认替换里的 `\n`。
- node 常在 fnm 里，非交互 shell 的 PATH 拿不到。
- 系统 python 没 pyyaml 且 PEP 668 挡 pip，建个 venv。
- 备份别都用同一个文件名（`config.yaml` 在 hermes 和 litellm 下同名会互相覆盖）。

---

## 8. 安全底线

- codeg 的 Web 端口（3080）**只监听 loopback**，对外走 Nginx 反代；
  需要时用 iptables `! -i lo --dport 3080 -j DROP` 兜一层，**不要在云防火墙放开 3080**。
- 密钥文件 600，只走 SSH 传输，**不要贴进任何聊天窗口或日志**。
- 密码登录能关就关，用公钥。

---

## 9. 验证（不验证不算做完）

**不能只看配置文件**，每个 agent 发一条真实请求：

```
PROMPT="Reply with exactly: PONG"
```

- 有 CLI 的直接跑（kimi / hermes / grok / codebuddy / openclaw / `opencode run`）。
- **ACP-only 的（pi / claude_code / cline / codex）走 ACP 测**：
  `initialize` → `session/new` → `session/prompt`，收 `agent_message_chunk`。
  这跟 codeg 走同一条路，最权威。
- 模型层面：把本机可用清单里的**每一个**都打一遍，列 OK/FAIL。
- 区分失败原因：**未登录 / 缺 key**（跟配置无关）vs **模型侧拒答** vs **配置错误**。

---

## 10. 汇报格式

```
## 现状
<盘点结果>

## 改动
<每条：文件或表 → 改了什么 → 为什么>

## 验证
agent:  11/11 通过（列出）
模型:   ocg 28/29、ccg 60/61、ds 2/2、ark 14/14
失败:   <逐条，附原因：上游限流 / 套餐外 / 未登录 / 配置问题>

## 备份位置
<路径>

## 我不确定 / 需要你决定的
<列出来>
```

**遇到不确定的先问，不要自己猜着改。**
