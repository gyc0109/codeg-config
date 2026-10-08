# codeg 配置项目

把 codeg 上这套 **OpenCode Go 多模型路由** 的完整配置与文档固化下来。

解决的核心问题：codeg 里 15 个 agent 各有自己的协议要求（Anthropic / OpenAI chat / Responses），
而 OpenCode Go 的 35 个模型并非三种协议全支持。直接填 base URL 会大量报
`503 Endpoint is unavailable`。本项目记录如何用两层网关把这件事解决。

---

## 架构

```
                      ┌─────────────────────────────────────────┐
   Claude Code ───────┤                                         │
   （Anthropic 协议）  │  LiteLLM  :4000                        │
                      │  Anthropic ⇄ OpenAI chat 协议转换      │
   Codex ─────────────┤  + 按模型分流（responses 直通）        │──▶ opencode-go-proxy :8899
   （Responses 协议）  │                                         │    注入 x-opencode-session
                      └─────────────────────────────────────────┘    注入真实 API key
                                                                        │
   opencode ┐                                                            │
   kimi     │                                                            │
   hermes   ├──────────────── 原生 OpenAI chat，直接连 ──────────────────┤
   grok     │                                                            │
   cline    │                                                            │
   pi       ┘                                                            │
                                                                        ▼
                                                          OpenCode Go（35 个模型）
```

### 两个网关的分工

| 组件 | 端口 | 职责 | 谁在用 |
| --- | --- | --- | --- |
| `opencode-go-proxy` | 8899 | 只做**连接层**：注入网关必需的 `x-opencode-session` 头、集中保管真实 key | 8 个 chat 协议 agent |
| `LiteLLM` | 4000 | 只做**协议层**：把 Anthropic / Responses 请求翻译成 OpenAI chat | Claude Code、Codex |
| `commandcode-proxy` | 8898 | Command Code 专用：把 `messages` 里的 `system` 角色提到顶层 + 注入 CC key | Claude Code（Command Code 槽位） |

分层的原因：协议翻译层出问题只会影响 Claude / Codex，其余 6 个 agent 不受牵连。
真实 API key 只存在 `/etc/opencode-go-proxy.env`（600 权限），其余配置一律写 `local` 占位。

---

## 双供应商：OpenCode Go + Command Code GOAT

除 OpenCode Go 外，本项目同时接入了第二个供应商 **Command Code GOAT**
（`https://api.commandcode.ai/provider/v1`，GOAT 套餐 $10/月，~57 个实测可用模型）。

**命名前缀**（所有 agent 的模型名统一带前缀，一眼区分来源）：

| 前缀 | 供应商 | 含义 |
| --- | --- | --- |
| `ocg/` | OpenCode Go | 例：`ocg/space-bunny-free` |
| `ccg/` | Command Code GOAT | 例：`ccg/claude-sonnet-5-5` |

**注意前缀是「别名」不是「真实 id」**：每个 agent 都把别名映射回上游真正要的 model id
（`ocg/space-bunny-free` → 上游 `space-bunny-free`）。各 agent 的实现方式不同：

### codeg 的模型分组怎么来的（影响 UI 显示）

codeg 前端把 agent 上报的 model configOption 拆成「分组 + 条目」
（代码在 web chunk `5e84a74a31a6c31b.js` 的 `deriveModelGroups`）：

| UI 元素 | 取自 |
| --- | --- |
| 分组 **key** | `option.value` 里第一个 `/` 之前的部分 |
| 分组 **显示名** | 该组内所有 `option.name` 的**公共 head**（同样按第一个 `/` 切） |
| 条目文字 | `option.name` 去掉 head 后的 tail |

所以：**要改分组显示名就改 `option.name` 的 head；`option.value` 必须保持
`ocg/<id>` 不动**（选完后回传时 agent 靠它路由）。

| Agent | option.name 形式 | 分组显示 |
| --- | --- | --- |
| opencode | `OpenCode Go/DeepSeek V4 Flash` | OpenCode Go ✅ |
| pi | `OpenCode Go/OCG DeepSeek V4 Flash` | OpenCode Go ✅（靠 `pi-acp-provider-label-patch`） |
| open_claw | 不暴露 model configOption（模型在它自己的配置里选） | — |

> pi 的坑：`pi-acp` 把 `option.name` 硬编码成 `${providerId}/${模型名}`，providerId 就是
> `ocg`/`ccg`，于是 UI 分组名变成了缩写。`option.value` 又不能改（回传要路由），
> 所以用 `install/pi-acp-provider-label-patch` **只改 name、不动 value**；显示名直接
> 读 pi 自己的 `~/.pi/agent/models.json`（单一数据源）。补丁幂等，并用 codeg 的
> systemd drop-in 在每次启动前重打（防 pi-acp 升级冲掉）。

- opencode / kimi：模型段自带 `id`（opencode）或 `model`（kimi）字段，天然支持别名
- hermes：靠 provider 的 `name` 转 slug（`OCG ...` / `CCG ...`）
- pi：用 provider 名当命名空间（models.json 里定义 provider `ocg` / `ccg`）
- codex：catalog 的 `display_name` 加前缀，`slug` 仍是真实 id
- claude_code：LiteLLM 的 `model_name` 改成 `ocg/<真实id>`；Command Code 侧由
  `commandcode-proxy` 剥掉 `ccg/`


### OpenCode Go 模型变更（2026-10 实测）

**`space-bunny-free` 已下线**（改成付费的 `space-bunny`）。免费档只剩
**`longcat-2.5-preview-free`**，因此所有默认模型改用它。

实测 37 个模型（权威来源 `GET /zen/go/v1/models`）：

| 分类 | 数量 | 说明 |
| --- | --- | --- |
| chat 可用 | **28** | 所有 chat agent |
| responses 可用 | **11** | codex |
| 两种都不可用 | 3 | `claude-haiku-5-5`（套餐外）、`minimax-m2.7`、`qwen3.8-max`（messages 报 Invalid credential） |

> 注意 `GET /zen/go/v1/models` **只返回 id**，不带上下文窗口；上下文要从
> opencode 的 models.dev 缓存 `~/.cache/opencode/models.json` 取（provider `opencode-go`）。

**LiteLLM 的 ocg/ 必须是 chat ∪ responses 的并集（34 个）**，不能只放 responses 子集——
因为 cline / code_buddy / grok / deepseek 走的是 LiteLLM 的 **chat** 端点，
只放 responses 子集会让它们连默认模型都找不到。

另：LiteLLM 配置里 `additional_drop_params` 用了 YAML 锚点 `&id001`。重建 ocg 段时
**必须先确保锚点还在**（它原本挂在第一条 ocg 条目上，删掉就会 `found undefined alias`）。


### 第三个供应商：DeepSeek 官方（`ds/`）

| 前缀 | 上游 | 鉴权 |
| --- | --- | --- |
| `ds/` | `https://api.deepseek.com` | `/etc/deepseek-official-key`（600） |

模型：`ds/deepseek-flash`（V4.1-Flash, 1M ctx, 393K out, 支持图片）、
`ds/deepseek-v4-pro`（1M ctx, 纯文本）。两个 id 与 OpenCode Go 的**重名**，
所以必须靠前缀区分。

**:8899 已升级为按前缀分流的本机路由**（原来是单纯转发到 OpenCode Go）：

```
ocg/<id>  ->  https://opencode.ai/zen/go/v1   （注入 x-opencode-session + key）
ds/<id>   ->  https://api.deepseek.com/v1     （注入 Bearer）
<id>      ->  https://opencode.ai/zen/go/v1   （无前缀，向后兼容）
```

LiteLLM（:4000）另加了 `ds/` 两条（转发给 :8899）。

> **代理的两个坑（都会造成间歇性 "Connection error"）**
>
> 1. `socket.create_connection(timeout=30)` 的 30s **对后续所有读写都生效**，
>    而模型推理经常超过 30s → `TimeoutError: read operation timed out`。
>    建连后必须 `upstream.settimeout(900)`。
> 2. 响应头原样转发会带上上游的 `Connection: keep-alive`，但代理处理完就关 socket，
>    客户端复用已关闭的连接就报错。必须在**响应**侧改成 `Connection: close`
>    （注意不是请求侧——请求侧强制 close 会破坏 grok 之类的流式）。

### Command Code 模型清单怎么来的（重要）

**不要靠逐个探测猜协议**，`GET /provider/v1/models` 的每个模型都带
`supported_endpoints`，这是权威依据：

| `supported_endpoints` | 个数 | 能用于 |
| --- | --- | --- |
| `['/chat/completions','/responses']` | 67 | 两类 agent 都行 |
| `['/chat/completions']` | 9 | 仅 chat agent |
| `['/messages']` | 10 | 仅 Claude 协议 |

再叠上“套餐是否包含”（探测返回 `MODEL_NOT_IN_PLAN`）和“上游是否可用”
（`No available providers match`），当前 GOAT 套餐的**实际可用集**：

| 用途 | 数量 | 备注 |
| --- | --- | --- |
| chat 可用 | **57** | 所有 chat agent（opencode/kimi/hermes/pi/cline/grok/deepseek） |
| responses 可用 | **48** | codex（必须是 responses 的子集） |
| messages 可用 | **1** | 仅 `claude-sonnet-5-5` |
| 套餐外 | 14 | `gpt-5.5/5.4/6-sol/6-astra`、`gemini-3.5/3.6` 等 |
| 在套餐但上游不可用 | 5 | `MiniMax-M2.7`、`Qwen3.6-Plus`、`inkling`×2、`pixel-canary` |

### 各 agent 接入情况（全量审计）

| Agent | OCG | CCG | 前缀形式 | 实测 |
| --- | --- | --- | --- | --- |
| opencode (`open_code`) | ✅ 29 | ✅ 57 | `ocg/` `ccg/` 别名 | ✅ |
| kimi (`kimi_code`) | ✅ 29 | ✅ 57 | `ocg/` `ccg/` 别名 | ✅ |
| hermes | ✅ 29 | ✅ 57 | `OCG`/`CCG` 名 | ✅ |
| pi | ✅ 29 | ✅ 57 | provider `ocg`/`ccg` | ✅ |
| claude_code | ✅ 36 | ✅ 1 | `ocg/`(LiteLLM) `ccg/`(:8898) | ✅ |
| codex | ✅ 10 | ✅ 48 | catalog `OCG`/`CCG` | ✅ |
| grok | ✅ | ✅ `xai/grok-4.7` | 经 LiteLLM 前缀 | ✅ |
| deepseek | ✅ | ✅ `deepseek-v4.1-flash` | 经 LiteLLM 前缀 | ✅ |
| cline | ✅ | ✅ | 单 provider 指向 LiteLLM，改 model 字符串即可 | ✅ |
| code_buddy | ✅ 29 | ✅ 57 | `~/.codebuddy/models.json` + `CODEBUDDY_BASE_URL` | ✅ |
| **open_claw** | ✅ 29 | ✅ 57 | `models.providers` 自定义 `ocg`/`ccg` | ✅ |
| code_buddy | ~~❌~~ ✅ |  |  |  |

> pi 的坑：`models-store.json` 只是**模型缓存**，provider 定义在 **`models.json`**
> （`{"providers": {"<id>": {"name","baseUrl","apiKey","api","models":[…]}}}`，
> `models` 必须是**数组**）。往 models-store.json 里加 provider 是无效的。
> 内置的 `opencode-go` provider 无法删，但把 `auth.json` 里的 `opencode-go` 条目
> 移除后它就不再显示，避免与 `ocg` 重复。另外 `settings.json` 的
> `defaultProvider` 也要跟着改成 `ocg`，否则 pi 会静默回退到列表第一个模型
> （不报错，但 codeg 里显示的当前模型就跟实际不符了）。
>
> codex 的坑：1.13.1 已**删除** `wire_api = "chat"`（只能 `responses`），而 LiteLLM
> 只做 chat→responses 单向桥接，所以 codex 走 LiteLLM 时只能用 responses 兼容的模型
> （ocg 10 个 + ccg 48 个）。这跟「直连 :8899」的覆盖面一样，但不用再切 provider。
> 具体的 codex 模型配置：`model = "ocg/gpt-6-luna"` + `model_provider = "litellm-bridge"`。
>
> Claude Code 的坑：它会把 `system` 角色塞进 `messages`（mid-conversation-system
> beta），而 CC 的 `/provider/v1/messages` 比 Anthropic 严格，直接返回
> `400 Invalid input at messages.N.role`。试过但**无效**：
> `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS`、`ANTHROPIC_BETAS`（只能追加不能移除）、
> LiteLLM 透传。→ 所以必需 `commandcode-proxy`（:8898）把 `system` 提到顶层。
>
> open_claw 的坑（两个）：> 1. 它的 ACP 桥接（`openclaw acp`）**没有本地/内嵌模式**，必须连后台 Gateway
>    （loopback `127.0.0.1:18789`）。Gateway 未运行时直接报
>    `ACP bridge failed: connect ECONNREFUSED 127.0.0.1:18789`。
>    → `openclaw gateway install` 装的是 **systemd user 服务**，而 root 默认
>    `Linger=no`，所以还得 `loginctl enable-linger root` 才能开机自启
>    （否则 `systemctl --user` 也会因没有 D-Bus session 而拒绝执行）。
> 2. 它**不自带** Command Code provider，但支持在 `models.providers` 下自定义
>    （字段：`baseUrl` / `apiKey` / `api` / `models[]`，model 项必填 `id`+`name`）。
>    所以定义了 `ocg`（→ :8899）和 `ccg`（→ CC 直连，key 在配置里）两个 provider。
>    原来的 `agents.defaults.models` 用的是内置 `opencode-go/`，已换成带前缀的。
>
> hermes 的坑：模型是**两个**环境变量成对生效，缺一个就报
> `Unknown provider 'custom:xxx'`（或退回到 OpenRouter 报 401）：
>
> ```bash
> HERMES_INFERENCE_PROVIDER=custom:ocg-space-bunny-free   # provider 名转 slug（小写、非字母数字转 -）
> HERMES_INFERENCE_MODEL=space-bunny-free                # 上游真实 model id（不带前缀）
> ```
>
> `custom_providers[].name` 决定 slug（`OCG Space Bunny Free` → `ocg-space-bunny-free`），
> 改名字就会让 codeg 里已存的引用失效。`~/.hermes/config.yaml` 里对应
> `provider:` / `model:` 两个顶层键。
>
> LiteLLM 的坑：对**不带 `/`** 的模型名会做后缀匹配。所以 `space-bunny-free` 能
> “蒙对”到 `ocg/space-bunny-free`，但 `gpt-6-luna` 会歧义命中（ocg 和 ccg 都存在）
> 从而走错供应商。所有调用方都应写全 `ocg/` / `ccg/` 前缀。
>
> CodeBuddy 的坑：它默认走腾讯账号体系（`~/.codebuddy/.credentials.json`），没登录时
> 报“没有可用的登录凭据”。但它支持自托管端点，不需要登录：
>
> ```bash
> CODEBUDDY_BASE_URL=http://127.0.0.1:4000/v1   # 指向本机 LiteLLM
> CODEBUDDY_API_KEY=local
> CODEBUDDY_MODEL=ocg/space-bunny-free
> CODEBUDDY_DISABLE_BUILTIN_MODELS=1           # 隐藏腾讯内置模型
> ```
>
> 模型清单写在 `~/.codebuddy/models.json`（`{"models":[…],"availableModels":[…]}`，
> 每项需 `id`/`name`/`url`/`apiKey`；`url` 与 `apiKey` 支持环境变量插值）。
> CodeBuddy 会给自己的自定义模型 id 加上 `custom-local:` 前缀（`CustomModelIdPrefix`），
> 所以 ACP 里看到的 value 是 `custom-local:ocg/…`，但显示名和实际上线的 id 都是我们定的。

---

## 协议支持矩阵（实测）

OpenCode Go 的 35 个模型并非三种协议通吃，这是所有配置问题的根源：

| 协议 | 可用 | 说明 |
| --- | --- | --- |
| OpenAI chat | **28 / 35** | 覆盖最广，chat 协议 agent 直接用 |
| Anthropic `/v1/messages` | 15 / 35 | Claude 原本只能用这批，现在经 LiteLLM 扩展到 28 |
| Responses | 9 / 35 | Codex 原本只能用这批，现在经 LiteLLM 扩展到 28 |

**全协议都不通（选了一定报错，已从各 agent 清单移除）：**
`grok-4.6`、`grok-4.7`、`minimax-m2.7`、`muse-spark-1.2-contributor`、`muse-spark-1.3-contributor`

**只在 Responses 可用**（Codex 侧经 LiteLLM 直通保留，chat 侧已移除）：
`gpt-5.6-luna`、`gpt-6-luna`

---

## 目录结构

```
codeg-config/
├── README.md                 本文件
├── inventory.md               15 个 agent 的版本/模型/协议对照表
├── restore.sh                 一键还原全部配置（含 codeg 应用配置）
├── export.py                  从现网 codeg.db 导出配置（脱敏）
├── import_codeg_db.py         把配置写回 codeg.db（需先停 codeg）
├── install/
│   ├── opencode-go-proxy          :8899 代理脚本
│   ├── opencode-go-proxy.service
│   ├── opencode-go-proxy.env.example   密钥模板（真实文件在 /etc/）
│   ├── litellm/config.yaml         :4000 协议转换层配置
│   ├── litellm.service
│   ├── commandcode-proxy            Command Code 专用转换代理（system 角色归并）
│   ├── commandcode-proxy.service
│   ├── commandcode-proxy.env.example
│   ├── pi-acp-provider-label-patch  pi 分组名补丁（幂等）
│   ├── pi-acp-provider-label-dropin.conf
│   └── codeg-web-timeout-patch     前端超时补丁（开机自动重打）
├── config/                        各 agent 配置文件副本（已脱敏）
│   ├── codeg.env
│   ├── opencode-go-proxy.env
│   ├── claude/settings.json
│   ├── codex/config.toml
│   ├── codex-model-catalog.json
│   ├── kimi-code/config.toml
│   ├── hermes/config.yaml
│   ├── opencode/opencode.jsonc
│   ├── pi/models.json             pi 的 provider 定义（双供应商）
│   ├── openclaw/openclaw.json     OpenClaw 双 provider（ocg/ccg）+ gateway 配置
│   └── cline-providers.json
└── codeg-app/                     codeg 应用自身的配置（从 SQLite 导出，已脱敏）
    ├── agent_setting.json       15 个 agent 的启用状态/排序/环境变量/绑定 provider
    ├── model_provider.json      8 个模型提供商（4 个 OpenCode Go + 4 个 Command Code）
    ├── app_metadata.json        应用级设置（语言、终端、委派、浏览器工具…）
    ├── chat_channel.json        微信 / Telegram 渠道
    ├── folder.json              工作区目录
    └── skills.json              codeg 托管的 38 个技能
```

## codeg 自身的配置在哪

codeg 是 Rust 应用，配置分三处：

| 位置 | 内容 | 本项目是否收录 |
| --- | --- | --- |
| `/etc/codeg.env` | `CODEG_TOKEN` / 端口 / 静态目录 | ✓ config/ |
| `/etc/systemd/system/codeg.service.d/` | 开机自动重打前端补丁 | ✓ restore.sh 会写 |
| `~/.local/share/codeg/codeg.db` | agent 配置、模型提供商、应用设置、聊天渠道、工作区 | ✓ codeg-app/ |

`codeg.db` 里还有 `conversation` / `token_usage_*` / `work_task` 等表，那些是**用户数据不是配置**，
本项目**不导出**（聊天记录、用量统计留在本机）。

## 快速上手

```bash
# 1. 恢复真实密钥（不要提交到 git）
sudo cp install/opencode-go-proxy.env.example /etc/opencode-go-proxy.env
sudo chmod 600 /etc/opencode-go-proxy.env
# 编辑填入 OPENCODE_GO_API_KEY=<你的 key>

# 1b.（可选）启用 Command Code GOAT 作为第二个供应商
sudo cp install/commandcode-proxy.env.example /etc/commandcode-proxy.env
sudo chmod 600 /etc/commandcode-proxy.env
# 编辑填入 COMMANDCODE_API_KEY=<你的 key>
# 不建这个文件则 restore.sh 自动跳过 Command Code，只还原 OpenCode Go

# 2. 还原全部配置（会停 codeg 写库再启动，约 30 秒）
sudo ./restore.sh
# 先预览不改动：
sudo ./restore.sh --dry-run
```

### 备份当前配置

改动配置后重新导出，让仓库保持最新：

```bash
sudo python3 export.py
git add codeg-app/ && git commit -m "更新 codeg 配置快照"
```

`export.py` 自动脱敏：`web_service_token`、GitHub OAuth 令牌、各类 api_key 都会替换成
`${REDACTED}`。写回时遇到占位符会**跳过该字段、保留库中原值**，所以重复还原不会把真实凭据冲掉。

> `model_provider` 里指向 `commandcode.ai` 的行会由 `restore.sh` 在导入后
> 用 `/etc/commandcode-proxy.env` 的 key 重新回填（导出时它们被脱敏成 `${REDACTED}`）。

## 重要提醒

- **不要把真实 key 提交进 git**。本项目所有配置已脱敏为 `${OPENCODE_GO_API_KEY}` 占位符。
- `litellm.service` 声明了 `Requires=opencode-go-proxy.service`，代理挂了 LiteLLM 会一起停。
- 升级 agent 后，binary 缓存会残留旧版本（约 0.5~2G/次），需定期清理，命令见 `inventory.md`。
- LiteLLM 配置里 `additional_drop_params` 是必须的：Codex 发的 Responses 格式字段
  （`reasoning_effort` 是对象、`web_search_options` 等）上游不认，不丢弃会直接 400。
