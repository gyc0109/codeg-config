#!/usr/bin/env python3
"""把 Windows 交接包合成单个 markdown 文件，方便直接发给 PC。"""
import json
import os
import re

W = '/root/codeg-work'
B = os.path.join(W, 'windows-bundle')
OUT = os.path.join(W, 'WINDOWS-CODEG-KIT.md')

CCKEY = re.search(r'COMMANDCODE_API_KEY=(\S+)', open('/etc/commandcode-proxy.env').read()).group(1)
OCGKEY = re.search(r'OPENCODE_GO_API_KEY=(\S+)', open('/etc/opencode-go-proxy.env').read()).group(1)
DSKEY = open('/etc/deepseek-official-key').read().strip()
ARKKEY = open('/etc/volcengine-ark-key').read().strip()

KEYMAP = {CCKEY: '${COMMANDCODE_API_KEY}', OCGKEY: '${OPENCODE_GO_API_KEY}',
          DSKEY: '${DEEPSEEK_API_KEY}', ARKKEY: '${VOLCENGINE_ARK_KEY}'}


def redact(t):
    for k, v in KEYMAP.items():
        t = t.replace(k, v)
    return t


parts = []
parts.append("""# codeg 配置交接包（来自服务器）

> 发给 Windows PC 上的 agent，让它照着配。
> 生成自一台已经配好的 Linux 服务器。

## 给 agent 的第一句话（可直接复制）

```
这个目录里的内容来自一台已配好的服务器。请读完 WINDOWS-CODEG-KIT.md，
在这台 Windows PC 上照着配好 codeg 的 agent 与模型。

重要前提：
- 这台 PC 用 **cc-switch** 做代理。claude_code 和 codex 归它管，
  ~/.claude/settings.json 和 ~/.codex/config.toml **不要动**，先告诉我它们现在指向哪。
- 动手前先完整盘点现状给我看，写操作前先备份。
- 改完必须发真实请求实测，不能只看配置文件。
- 遇到不确定的先问我。
- 文档里的模型数量是那台服务器的账号权限；这台 PC 的 key 可能属于不同账号，
  配完要在这台机器上复测，有出入告诉我。

供应商 key 我另外给你。
```

---

## 目录

1. [目标架构](#1-目标架构)
2. [供应商 key](#2-供应商-key)
3. [模型清单](#3-模型清单)
4. [本地代理要处理的三件事](#4-本地代理要处理的三件事)
5. [各 agent 的接入方式](#5-各-agent-的接入方式)
6. [codeg 的 provider 定义](#6-codeg-的-provider-定义)
7. [必须知道的坑](#7-必须知道的坑)
8. [参考配置（服务器实际内容）](#8-参考配置)
9. [验证](#9-验证)
10. [⚠️ 账号权限可能不同](#10-账号权限可能不同)

---

## 1. 目标架构

**四家供应商，统一前缀：**

| 前缀 | 供应商 | 上游 | 特殊要求 |
| --- | --- | --- | --- |
| `ocg/` | OpenCode Go | `https://opencode.ai/zen/go/v1` | **必须带 `x-opencode-session` 头** |
| `ccg/` | Command Code GOAT | `https://api.commandcode.ai/provider/v1` | `/messages` 不接受 messages 里的 `role:system` |
| `ds/` | DeepSeek 官方 | `https://api.deepseek.com/v1` | 拒绝 `role:developer` |
| `ark/` | 火山方舟 | `https://ark.cn-beijing.volces.com/api/v3` | 模型名**必须带日期后缀**；拒绝 `role:developer` |

前缀是**别名**，转发前剥掉（`ocg/xxx` → 上游收 `xxx`）。

所有 agent 一律指向**本机代理**，由代理按前缀分流。

---

## 2. 供应商 key

服务器上文件名是（Windows 上位置可自定）：

| 环境变量 | 服务器文件 | 用途 |
| --- | --- | --- |
| `OPENCODE_API_KEY` | `/etc/opencode-go-proxy.env` | OpenCode Go |
| `COMMANDCODE_API_KEY` | `/etc/commandcode-proxy.env` | Command Code GOAT |
| `DEEPSEEK_API_KEY` | `/etc/deepseek-official-key` | DeepSeek 官方 |
| `VOLCENGINE_ARK_KEY` | `/etc/volcengine-ark-key` | 火山方舟 |

> ⚠️ 火山方舟的 key 是 **`ark-<uuid>-<数字>`** 这种格式，不是那个很长的 token。
> ⚠️ 真实 key 我不会写进这份文档，你单独发给我。

---

## 3. 模型清单

### 概要（服务器实测）

| 供应商 | chat 可用 | responses 可用 | 备注 |
| --- | --- | --- | --- |
| OpenCode Go | 30 | 11 | 其中 6 个是 **responses-only**，不能给 chat agent |
| Command Code GOAT | 54 | 47 | |
| DeepSeek 官方 | 2 | 2 | |
| 火山方舟 | 14 | 14 | |

### 两个集合必须分开

- **`chat_ok`** → 给所有 chat agent（pi / kimi / hermes / opencode / code_buddy / openclaw / cline / dsh）
- **`resp_ok`** → **只给 codex**。它是 `chat_ok` 的子集

塞错会报 `Model does not support this protocol`。

### 默认模型

| 供应商 | 默认 | 说明 |
| --- | --- | --- |
| OCG | `longcat-2.5-preview-free` | 免费档 |
| CCG | `stealth/glyph-cluster:free` | 免费 stealth 模型 |
| DS | `deepseek-flash` | |
| ARK | `doubao-seed-2-1-pro-260915` | |

### 完整清单

""")

# model-list.txt
ml = open(f'{B}/model-list.txt').read()
parts.append("```\n" + ml.rstrip() + "\n```\n")

# models.json
spec = json.load(open(f'{B}/models.json'))
parts.append("""
### 机器可读版（models.json）

```json
""" + json.dumps(spec, indent=2, ensure_ascii=False) + """
```

---

## 4. 本地代理要处理的三件事

Windows 上需要一个本地代理。可以直接用 Python 写（参考仓库
`mac/opencode-go-proxy.py`，单端口按前缀分流），或者装 LiteLLM
（参考 `install/litellm/config.yaml`）。

**无论哪种，这三件事必须处理：**

### ① OCG 的 session header

OpenCode Go 拒绝任何不带 session 头的请求。大多数 agent 不会发，代理要补：

```
headers["x-opencode-session"] = <uuid4>
headers["Authorization"] = "Bearer " + OCG_KEY
```

### ② CC 的 `/messages` 要提 system

CC 的 Anthropic 端点比 Anthropic 自己严格：**messages 数组里出现 `role:"system"`
直接 400** `Invalid input at messages.N.role`。

Claude Code 经常把环境/上下文块作为 system turn 塞进 messages，所以代理要把它们
合并到顶层 `system` 字段，并保证 `messages` 以 user 开头。

### ③ ds/ark 拒 `developer`

DeepSeek 和 Ark 收到 `role:"developer"` 会 422。代理要把 `messages[].role`
从 `developer` 改写成 `system`。

### 参考实现（Python 核心逻辑）

```python
def _split_model(model):
    for pre in ("ocg", "ccg", "ds", "ark"):
        if model.startswith(pre + "/"):
            return pre, model[len(pre) + 1:]
    return "ocg", model          # 无前缀默认走 OCG

UPSTREAM = {
    "ocg": ("opencode.ai",              "/zen/go/v1",  OCG_KEY,  "ocg"),
    "ccg": ("api.commandcode.ai",       "/provider/v1", CC_KEY,   "cc"),
    "ds":  ("api.deepseek.com",         "/v1",         DS_KEY,   "ds"),
    "ark": ("ark.cn-beijing.volces.com", "/api/v3",    ARK_KEY,  "ark"),
}

# 转发前：
#   doc["model"] = wire                       # 剥前缀
#   if pre == "ccg" and "/messages" in path:  提 system
#   if pre in ("ds", "ark"):                  developer -> system
#   if pre == "ocg":                          headers["x-opencode-session"] = uuid4()
```

---

## 5. 各 agent 的接入方式

统一的"别名层"实现各不相同：

| Agent | 配置位置（Windows） | 机制 |
| --- | --- | --- |
| `pi` | `%USERPROFILE%\\.pi\\agent\\models.json` | 定义 provider `ocg`/`ccg`/`ds`/`ark`；`models` 是**数组** |
| `opencode` | `%USERPROFILE%\\.config\\opencode\\opencode.jsonc` | `provider.<id>.models`；加 `"disabled_providers":["opencode-go"]` |
| `kimi_code` | `%USERPROFILE%\\.kimi-code\\config.toml` | 模型段自带 `model` 字段 |
| `hermes` | `%USERPROFILE%\\.hermes\\config.yaml` | `custom_providers`，靠 **name 转 slug** |
| `code_buddy` | `%USERPROFILE%\\.codebuddy\\models.json` | 配合 env `CODEBUDDY_*` |
| `open_claw` | `%USERPROFILE%\\.openclaw\\openclaw.json` | `models.providers` + allowlist |
| `cline` | `%USERPROFILE%\\.cline\\data\\settings\\` | **两个文件**，见坑 |
| `dsh` | `%USERPROFILE%\\.dsh\\settings.yaml` | |
| `codex` | — | **归 cc-switch，不要动** |
| `claude_code` | — | **归 cc-switch，不要动** |

---

## 6. codeg 的 provider 定义

各 agent 在 codeg UI 里绑定的 provider。`apiUrl` 指向本地代理。

```json
{json.dumps(json.load(open(f'{B}/providers.json')), indent=2, ensure_ascii=False)}
```

> `claude_code` 和 `codex` 那两项：如果它们的 cc-switch 已经工作，**不要建**。
> 只在需要「从 codeg UI 里切换供应商」时才建。

---

## 7. 必须知道的坑

这一节都是实际踩过的，按重要性排。

### cline（最容易踩，缺一个就"看起来配好了但用不了"）

1. **环境变量是 `CLINE_PROVIDER` / `CLINE_BASE_URL` / `CLINE_API_KEY` / `CLINE_MODEL`**，
   不是 `OPENAI_*`。用错会退回官方 Cline 账号，报
   `Unauthorized: Please make sure you're using the latest version of Cline and re-authenticate your Cline account`
2. **cline 的可选模型不读 `providers.json`**，读同目录的 `models.json`。
   缺了就只有 `gpt-4o` 一个选项，一请求就
   `Invalid model name passed in model=gpt-4o`

### open_claw

1. **`agents.entries` 必须非空**（`{"main": {}}`），否则网关起不来，报
   `agents.entries must contain at least one configured agent`。
   → `openclaw doctor --fix` 修
2. doctor 会把 `agents.defaults.models` **迁移成 `agents.defaults.modelPolicy.allow`**。
   之后改 allowlist **要改 `modelPolicy.allow`**，改 `models` 不生效
3. 默认模型在 `agents.defaults.model.primary`。如果它指向认证失败的 provider
   （比如从别处带来的 `cherry-*`），**整个 agent 直接失败**，报
   `All models failed ... has auth issue`。要改成可用的

### pi

`pi-acp` 只是 ACP 适配器，**还需要主程序**：
```powershell
npm i -g @earendil-works/pi-coding-agent
```
否则 `session/new` 报 `Could not start pi: executable not found (command: pi)`。

`settings.json` 的 `defaultProvider` / `defaultModel` 要一起改，
否则静默回退到列表第一个模型（不报错，但实际模型和显示不一致）。

### kimi

- `default_model` 必须在**文件顶部**。放到某个 `[models."..."]` 段之后，
  它会被解析成那个段的键，然后报 "no default model configured"
- **每个 `[providers.*]` 段里还各有一个 `default_model`**，很容易漏

### 模型下线时的全盘搜索

供应商会上下线模型（例：`stealth/space-bunny-alpha` 官方公告 free preview 结束）。
下线后仍被引用的位置（都是历史踩过的）：

- `~/.pi/agent/settings.json` 的 `defaultModel`
- **kimi 每个 `[providers.*]` 段的 `default_model`**
- codeg DB `model_provider` 表的 `model` 字段
- codeg DB `agent_setting` 的 `env_json` 里的 `*_MODEL` 变量
- `open_claw` 的 `modelPolicy.allow`
- 部署/还原脚本里的健康检查用的模型名

### 备份

复制备份时注意**同名文件会互相覆盖** —— LiteLLM 和 hermes 的配置**都叫 `config.yaml`**，
用 basename 复制的话你的"备份"就是错的。加路径前缀区分。

---

## 8. 参考配置

以下是服务器上各 agent 的实际配置（key 已脱敏），供结构和字段名参考。

""")

REFS = [
    ('pi — %USERPROFILE%\\.pi\\agent\\models.json', '/root/.pi/agent/models.json', 'json'),
    ('kimi — %USERPROFILE%\\.kimi-code\\config.toml', '/root/.kimi-code/config.toml', 'toml'),
    ('hermes — %USERPROFILE%\\.hermes\\config.yaml', '/root/.hermes/config.yaml', 'yaml'),
    ('opencode — %USERPROFILE%\\.config\\opencode\\opencode.jsonc', '/root/.config/opencode/opencode.jsonc', 'jsonc'),
    ('code_buddy — %USERPROFILE%\\.codebuddy\\models.json', '/root/.codebuddy/models.json', 'json'),
    ('dsh — %USERPROFILE%\\.dsh\\settings.yaml', '/root/.dsh/settings.yaml', 'yaml'),
]
for title, path, lang in REFS:
    if not os.path.exists(path):
        continue
    t = redact(open(path).read())
    parts.append(f"### {title}\n\n```{lang}\n{t.rstrip()}\n```\n\n")

# openclaw 太大，只取关键片段
oc = json.load(open('/root/.openclaw/openclaw.json'))
snippet = {
    "models": {"providers": {k: {"baseUrl": v.get("baseUrl"), "apiKey": "local",
                                 "api": v.get("api"),
                                 "models_count": len(v.get("models", [])),
                                 "_models_sample": [m.get("id") for m in v.get("models", [])[:3]]}
                            for k, v in oc["models"]["providers"].items()
                            if k in ("ocg", "ccg", "ds", "ark")}},
    "agents": {"defaults": {"model": oc["agents"]["defaults"].get("model"),
                            "modelPolicy": {"allow_count": len(
                                (oc["agents"]["defaults"].get("modelPolicy") or {}).get("allow") or []),
                                "_sample": ((oc["agents"]["defaults"].get("modelPolicy") or {})
                                            .get("allow") or [])[:3]},
                            "models_count": len(oc["agents"]["defaults"].get("models") or {})},
               "entries": oc["agents"].get("entries")},
}
parts.append(f"### open_claw — %USERPROFILE%\\.openclaw\\openclaw.json（节选）\n\n"
             f"```json\n{json.dumps(snippet, indent=2, ensure_ascii=False)}\n```\n\n")

# cline
cdir = '/root/.cline/data/settings'
if os.path.isdir(cdir):
    parts.append("### cline — %USERPROFILE%\\.cline\\data\\settings\\providers.json\n\n"
                 f"```json\n{redact(open(os.path.join(cdir,'providers.json')).read()).rstrip()}\n```\n\n")
    mj = json.load(open(os.path.join(cdir, 'models.json')))
    p = mj['providers']['openai-compatible']
    parts.append("### cline — %USERPROFILE%\\.cline\\data\\settings\\models.json（结构示例）\n\n"
                 f"```json\n{json.dumps({'version':1,'providers':{'openai-compatible':{'provider':p['provider'],'models':dict(list(p['models'].items())[:2]),'discoveredModelIds':p['discoveredModelIds'][:2]}}}, indent=2, ensure_ascii=False)}\n```\n\n")

parts.append("""---

## 9. 验证

**不验证不算做完。**

```powershell
# 通用探针
curl.exe -s http://127.0.0.1:<端口>/v1/chat/completions `
  -H "Content-Type: application/json" `
  -d '{{"model":"ocg/longcat-2.5-preview-free","messages":[{{"role":"user","content":"Reply with exactly: PONG"}}],"max_tokens":2000}}'
```

1. **代理四条链路**各测一次（ocg / ccg / ds / ark）
2. **每个模型都打一遍**，列 OK/FAIL
3. **每个 agent 都发一条真实请求**：
   - 有 CLI 的直接跑（`kimi -p`、`hermes -z`、`grok -p`、`codebuddy -p`、
     `openclaw agent -m`、`opencode run`）
   - **ACP-only 的（pi / claude_code / cline / codex）走 ACP 协议测**：
     `initialize` → `session/new` → `session/prompt`，收 `agent_message_chunk`。
     这跟 codeg 走的是同一条路，最权威
4. 失败要区分：
   - **上游限流 / 套餐外 / 账号无权限** → 不是配置问题
   - **配置引用了已下线模型** → 必须修

---

## 10. ⚠️ 账号权限可能不同

**模型的可用集取决于 key 属于哪个账号。** 实测例证：同一个 Command Code 供应商，
两台机器：

| | 机器 A | 机器 B |
| --- | --- | --- |
| chat 可用 | 54 | **50** |
| responses 可用 | 47 | **44** |

机器 B 少了 6 个（`Qwen3.6-Max-Preview` 报 404；`gemini-3.7-flash`、
`muse-spark-1.2/1.2-contributor/1.3/1.3-contributor` 报 403），
又多了 2 个（`poolside/laguna-s-2.1-free`、`xiaomi/mimo-v2.5`）。

**所以上面第 3 节的清单是起点，不是终点。** 配完要在这台 PC 上用同样的方法复测：

```powershell
# OCG
curl.exe -s "https://opencode.ai/zen/go/v1/models" `
  -H "Authorization: Bearer $env:OPENCODE_API_KEY" -H "x-opencode-session: probe"

# CC（每项带 supported_endpoints，是协议判定的权威依据）
curl.exe -s "https://api.commandcode.ai/provider/v1/models" `
  -H "Authorization: Bearer $env:COMMANDCODE_API_KEY"
```

CC 的判定口径：
- 先按 `supported_endpoints` 分协议（`/chat/completions` / `/responses` / `/messages`）
- 再逐个打 `/chat/completions`：
  - `MODEL_NOT_IN_PLAN` → 套餐外
  - `Model not exist` / `Authentication failed` → **本机账号无权限**
  - `No available providers match` → 上游临时挂了

---

## 汇报格式

```
## 现状
<盘点结果，含 cc-switch 现在管哪些 agent、监听哪个端口>

## 改动
<每条：文件 → 改了什么 → 为什么>

## 验证
代理链路:  4/4
模型:      N/M   （失败逐条 + 原因）
agent:     N/M

## 备份位置
<路径>

## 需要你决定的
<列出来>
```
""")

open(OUT, 'w').write('\n'.join(parts))
print(f"  ✓ {OUT}")
print(f"    大小: {os.path.getsize(OUT)/1024:.1f} KB")
print(f"    行数: {sum(1 for _ in open(OUT))}")
