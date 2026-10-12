# PROMPT-REFRESH-MODELS：只刷新模型清单

用这个提示词，当**配置已经就绪**、只是要更新模型列表时用（供应商上线下线模型、
套餐变更、换了 key）。

整段复制给目标机器上的 agent：

```
read https://raw.githubusercontent.com/gyc0109/codeg-config/main/PROMPT-REFRESH-MODELS.md
按它的流程刷新这台机器上 codeg 各 agent 的模型清单。

我这台机器：<新机器 / 服务器 / Mac>
代理方式：<codeg 自建代理，端口 ... / LiteLLM :4000 / 其他>
key 在：<路径>

改完给我实测结果，别只改配置。
```

---

## 流程

### 第 1 步：备份

```bash
BK=~/codeg-model-refresh-$(date +%Y%m%d-%H%M%S); mkdir -p "$BK"
# 把要改的配置文件 + codeg.db 都复制进去
# ⚠️ 注意文件名冲突：litellm 和 hermes 的配置文件都叫 config.yaml，
#    复制时要加路径前缀区分，否则互相覆盖，你的"备份"就是错的
```

### 第 2 步：拉取新列表

```bash
# OpenCode Go（只返回 id，没有上下文窗口）
curl -sS https://opencode.ai/zen/go/v1/models \
  -H "Authorization: Bearer $OCG_KEY" -H 'x-opencode-session: probe' > ocg_models.json

# Command Code（每项带 supported_endpoints，协议判定的权威依据）
curl -sS https://api.commandcode.ai/provider/v1/models \
  -H "Authorization: Bearer $CC_KEY" > cc_models.json
```

跟上次的清单对比，**先看差集**：新增了什么、下线了什么。

### 第 3 步：⚠️ 用本机 key 全量重测

**这一步不能省，也不能照抄别台机器的结果。**

每台机器的 key 可能属于不同账号，套餐权限不同。实测差异例证：
同一个 CC 供应商，机器 A 有 54 个 chat 可用，机器 B 只有 50 个，
且 B 还多出 2 个 A 没有的。

```
OCG:  对每个模型分别打 /chat/completions 和 /responses
CC:   先按 supported_endpoints 分协议，再逐个打 /chat/completions 判套餐
      MODEL_NOT_IN_PLAN       -> 套餐外
      Model not exist         -> 该账号无权限
      Authentication failed   -> 该账号无权限
      No available providers  -> 上游挂了（临时的）
ds/ark: 量小直接打
```

产出两个集合：

- `chat_ok` = (both ∪ chat_only) − 套餐外 − 不可用
- `resp_ok` = both − 套餐外 − 不可用 ← **给 codex 用，是 chat_ok 的子集**

常见误判：把 responses-only 的模型塞进 chat 列表，agent 一选就报
`Model does not support this protocol`。

### 第 4 步：重建各 agent 配置

按 `chat_ok` 重建（**不是** `resp_ok`，除非该 agent 只走 responses）：

| Agent | 文件 |
| --- | --- |
| pi | `~/.pi/agent/models.json` |
| opencode | `~/.config/opencode/opencode.jsonc` |
| kimi_code | `~/.kimi-code/config.toml` |
| hermes | `~/.hermes/config.yaml` |
| code_buddy | `~/.codebuddy/models.json` |
| open_claw | `~/.openclaw/openclaw.json` |
| cline | `~/.cline/data/settings/models.json`（**不是** providers.json） |
| dsh | `~/.dsh/settings.yaml` |
| codex | `~/.codex/codeg-model-catalog.json`（**用 resp_ok**） |
| LiteLLM | `/opt/litellm/config.yaml`（`ocg/` 用 chat ∪ resp） |

**同时检查旧模型有没有被引用在别处** —— 这是最容易漏的：

```bash
# 全盘找已下线的模型名
for m in <下线的模型列表>; do
  grep -rl "$m" ~/.pi ~/.kimi-code ~/.hermes ~/.config/opencode ~/.codebuddy \
    ~/.openclaw ~/.cline ~/.dsh ~/.codex ~/.claude /opt/litellm 2>/dev/null
done
```

历史踩过的坑（都是"模型下线了但配置还在引用"）：
- `~/.pi/agent/settings.json` 的 `defaultModel`
- **`~/.kimi-code/config.toml` 里每个 `[providers.*]` 段各自的 `default_model`**
- codeg DB 里 `model_provider` 表的 `model` 字段
- codeg DB 里 `agent_setting` 的 `env_json`（`*_MODEL` 变量）
- `open_claw` 的 `modelPolicy.allow`（doctor 迁移后真正生效的地方）
- `restore.sh` 之类脚本里的健康检查用的模型名

### 第 5 步：重启相关服务

```bash
# Linux
systemctl restart opencode-go-proxy litellm commandcode-proxy codeg
# macOS
launchctl bootout gui/$(id -u)/app.codeg.opencode-go-proxy
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/app.codeg.opencode-go-proxy.plist
# open_claw（两边都是）
openclaw gateway restart
```

### 第 6 步：验证

1. **每个模型都打一遍**，列出 OK/FAIL
2. **每个 agent 都发一条真实请求**（`Reply with exactly: PONG`），
   ACP-only 的（pi/claude_code/cline/codex）走 ACP 协议测
3. codeg DB 里的 provider 引用重新校验一遍

失败的要区分：
- **上游限流 / 套餐外 / 该账号无权限** → 不是配置问题，记下来即可
- **配置引用了已下线模型** → 必须修

### 第 7 步：同步仓库

```bash
cd <repo>
# 复制新配置，但把 key 换成 ${...} 占位符
git commit -m "刷新模型清单：ocg N -> M，ccg X -> Y"
git push
```

**推送前检查有没有把真实 key 提交上去。**

---

## 汇报格式

```
## 变化
OCG:  37 -> 38（+step-5-preview-free）
CCG:  chat 57 -> 54，resp 48 -> 47
      + Qwen3.6-Plus, mistral-large-4
      - space-bunny-alpha（官方公告 free preview 结束）
ds/ark: 不变

## 修掉的失效引用
<文件 → 从什么改成什么>

## 验证
模型:  95/96
agent: 11/11
失败:  <逐条 + 原因>

## 备份
<路径>
```
