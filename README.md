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

分层的原因：协议翻译层出问题只会影响 Claude / Codex，其余 6 个 agent 不受牵连。
真实 API key 只存在 `/etc/opencode-go-proxy.env`（600 权限），其余配置一律写 `local` 占位。

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
├── restore.sh                 一键还原全部配置
├── install/
│   ├── opencode-go-proxy          :8899 代理脚本
│   ├── opencode-go-proxy.service
│   ├── opencode-go-proxy.env.example   密钥模板（真实文件在 /etc/）
│   ├── litellm/config.yaml         :4000 协议转换层配置
│   ├── litellm.service
│   └── codeg-web-timeout-patch     前端超时补丁（开机自动重打）
├── config/                        各 agent 配置副本（已脱敏）
│   ├── codeg.env
│   ├── opencode-go-proxy.env
│   ├── claude/settings.json
│   ├── codex/config.toml
│   ├── kimi-code/config.toml
│   ├── hermes/config.yaml
│   ├── opencode/opencode.jsonc
│   └── cline-providers.json
└── docs/                          原始数据快照
```

## 快速上手

```bash
# 1. 恢复真实密钥（不要提交到 git）
sudo cp config/opencode-go-proxy.env.example /etc/opencode-go-proxy.env
sudo chmod 600 /etc/opencode-go-proxy.env
# 编辑填入 OPENCODE_GO_API_KEY=<你的 key>

# 2. 还原全部配置
sudo ./restore.sh

# 3. 验证
systemctl status opencode-go-proxy litellm
```

## 重要提醒

- **不要把真实 key 提交进 git**。本项目所有配置已脱敏为 `${OPENCODE_GO_API_KEY}` 占位符。
- `litellm.service` 声明了 `Requires=opencode-go-proxy.service`，代理挂了 LiteLLM 会一起停。
- 升级 agent 后，binary 缓存会残留旧版本（约 0.5~2G/次），需定期清理，命令见 `inventory.md`。
- LiteLLM 配置里 `additional_drop_params` 是必须的：Codex 发的 Responses 格式字段
  （`reasoning_effort` 是对象、`web_search_options` 等）上游不认，不丢弃会直接 400。
