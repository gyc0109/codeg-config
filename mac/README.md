# Mac（gyc 的主力机）配置存档

与服务器**架构不同**：Mac 没有 LiteLLM，用 cc-switch(:15721) + 自建 Python 代理(:15825)。

## 路由

`~/.codeg/opencode-go-proxy.py`（launchd: `app.codeg.opencode-go-proxy`，端口 15825）
被改成了**双上游路由**，按模型名前缀分流：

| 模型名前缀 | 上游 | 鉴权 |
| --- | --- | --- |
| `ocg/<id>` | `https://opencode.ai/zen/go` | `~/.codeg/opencode-go-key` + 注入 `x-opencode-session` |
| `ccg/<id>` | `https://api.commandcode.ai/provider/v1` | `~/.codeg/commandcode-goat-key` |
| 无前缀 | OpenCode Go（兼容旧行为） | 同上 |

`ccg/` 走 `/messages` 时会把 `messages` 里的 `system` 角色提到顶层 `system`
（Command Code 比 Anthropic 严格，否则 400 `Invalid input at messages.N.role`）。

## 各 agent

| agent | 接法 | 前缀形式 |
| --- | --- | --- |
| opencode | `provider` key = `ocg`/`ccg` + `disabled_providers:["opencode-go"]` | value `ocg/…` `ccg/…` |
| kimi | `[providers.*]` + `[models."ocg/…"]` | 别名 |
| hermes | `custom_providers`（name → slug） | `OCG`/`CCG` 名 |
| pi | `models.json` 的 providers `ocg`/`ccg` | provider 命名空间 |
| cline / code_buddy | codeg env 指向 :15825 | `ocg/…` |
| claude_code / codex | codeg 里新增 CC provider → :15825 | `ccg/…` |
| open_claw | `models.providers.ocg`/`ccg` | provider 命名空间 |

## 踩过的坑

1. **`default_model` 必须写在 TOML 文件开头**。写在末尾会被解析成最后一个
   `[models."…"]` 段的键，顶层拿不到 → kimi 报 `no default model configured`。
2. **hermes 的 slug 规则是 `name.lower().replace(" ", "-")`**，只把空格换成连字符，
   **点号/括号原样保留**：
   - `CCG DeepSeek V4.1 Flash` → `custom:ccg-deepseek-v4.1-flash`（点号保留！）
   - `CCG DeepSeek V4 Flash (latest)` → `custom:ccg-deepseek-v4-flash-(latest)`
3. **Zen 不能自定义 provider**：服务端 `FreeTierError: only be used from within
   OpenCode`，伪造完整 UA / `x-session-*` 头均无效，只能保留内置 `opencode` provider。

## 端点

- 154.37.213.158:**7223**（不是 Kali 的 7222），用户 gyc
- codeg token 在 DB 的 `app_metadata.web_service_token`
