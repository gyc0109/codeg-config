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

**命名前缀**（用于在模型列表里一眼区分来源）：

| 前缀 | 供应商 | 说明 |
| --- | --- | --- |
| `ocg/` | OpenCode Go | 有别名层的 agent 使用 |
| `ccg/` | Command Code GOAT | 同上 |

有 provider 列/分组显示的 agent（pi、opencode、hermes、codex）直接靠 provider 名区分，
无别名层的 agent（kimi）靠 `ocg/`、`ccg/` 前缀区分。

### Command Code 的三个坑（实测）

1. **Claude Code 会把 `system` 角色塞进 `messages`**
   （mid-conversation-system beta，环境块/上下文块）。Command Code 的
   `/provider/v1/messages` 比 Anthropic 严格，直接返回
   `400 Invalid input at messages.N.role`。
   → 用 `commandcode-proxy`（:8898）把 `system` 提到顶层 `system` 字段。
   试过但**无效**的手段：`CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS`、
   `ANTHROPIC_BETAS`（只能追加不能移除）、LiteLLM 透传（原样转发）。
2. **GOAT 套餐里只有 1 个 Claude 模型**：`claude-sonnet-5-5`，且只支持 `/messages` 协议。
3. **各 agent 接法不同**：

| Agent | 接法 | 配置文件 |
| --- | --- | --- |
| opencode | 多 provider，`ccg/` 前缀别名 | `~/.config/opencode/opencode.jsonc` |
| kimi | 多 provider，`ccg/` 前缀别名 | `~/.kimi-code/config.toml` |
| hermes | `custom_providers`（名字转 slug） | `~/.hermes/config.yaml` |
| pi | **`models.json`** 的 `providers` 段（不是 models-store.json！） | `~/.pi/agent/models.json` |
| codex | 第二个 `model_providers.commandcode` 块 | `~/.codex/config.toml` |
| claude_code | 经 `commandcode-proxy` :8898 | codeg provider #5 |
| grok / deepseek / kimi_code | codeg 里再加一个 provider，UI 切换 | codeg 应用配置 |

> pi 的坑：`models-store.json` 只是**模型缓存**，provider 定义在 **`models.json`**
> （`{"providers": {"<id>": {"name","baseUrl","apiKey","api","models":[…]}}}`，
> `models` 必须是**数组**）。往 models-store.json 里加 provider 是无效的。

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
