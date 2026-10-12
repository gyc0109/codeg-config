# codeg 配置交接包（来自服务器）

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


```
# OpenCode Go — chat 30 / responses 11
ocg/deepseek-flash
ocg/deepseek-v4-flash
ocg/deepseek-v4-flash-vision-exp
ocg/deepseek-v4-pro
ocg/deepseek-v4.1-flash
ocg/glm-5.1
ocg/glm-5.2
ocg/glm-5.3
ocg/glm-5.3-flash
ocg/hy3
ocg/hy4-preview
ocg/kimi-k2.6
ocg/kimi-k2.7-code
ocg/kimi-k3
ocg/longcat-2.0
ocg/longcat-2.5-preview-free
ocg/mimo-v2.5
ocg/mimo-v2.5-pro
ocg/mimo-v2.6-flash
ocg/mimo-v2.6-pro
ocg/minimax-m2.5
ocg/minimax-m3
ocg/omen-alpha
ocg/qwen3.6-plus
ocg/qwen3.7-max
ocg/qwen3.7-plus
ocg/qwen3.8-flash
ocg/qwen3.8-max
ocg/space-bunny
ocg/step-5-preview-free

# (仅 responses，共 6 个，勿用于 chat agent)
ocg/gpt-5.6-luna
ocg/gpt-6-luna
ocg/grok-4.6
ocg/grok-4.7
ocg/muse-spark-1.2-contributor
ocg/muse-spark-1.3-contributor

# Command Code GOAT — chat 54 / responses 47
ccg/MiniMaxAI/MiniMax-M2.5
ccg/MiniMaxAI/MiniMax-M3
ccg/Qwen/Qwen3.6-Max-Preview
ccg/Qwen/Qwen3.6-Plus
ccg/Qwen/Qwen3.7-Flash
ccg/Qwen/Qwen3.7-Max
ccg/Qwen/Qwen3.7-Plus
ccg/Qwen/Qwen3.8-27B
ccg/Qwen/Qwen3.8-Flash
ccg/Qwen/Qwen3.8-Max
ccg/Qwen/Qwen3.8-Max-0902
ccg/Qwen/Qwen3.8-Omni-Flash
ccg/deepseek/deepseek-v4-flash
ccg/deepseek/deepseek-v4-flash-fast
ccg/deepseek/deepseek-v4-flash-vision-exp
ccg/deepseek/deepseek-v4-pro
ccg/deepseek/deepseek-v4.1-flash
ccg/deepseek/deepseek-v4.1-flash-fast
ccg/google/gemini-3.7-flash
ccg/google/gemini-3.8-flash
ccg/gpt-5.6-luna
ccg/gpt-5.6-sol
ccg/gpt-6-luna
ccg/inclusionai/ling-3.1-flash:free
ccg/meituan/LongCat-2.0
ccg/meta/muse-spark-1.2
ccg/meta/muse-spark-1.2-contributor
ccg/meta/muse-spark-1.3
ccg/meta/muse-spark-1.3-contributor
ccg/mistral/mistral-large-4
ccg/moonshotai/Kimi-K2.5
ccg/moonshotai/Kimi-K2.6
ccg/moonshotai/Kimi-K2.7-Code
ccg/moonshotai/Kimi-K2.7-Code-Highspeed
ccg/moonshotai/Kimi-K3
ccg/nvidia/nemotron-3-ultra-550b-a55b
ccg/stealth/glyph-cluster:free
ccg/stepfun/Step-3.7-Flash
ccg/stepfun/Step-5-Preview
ccg/tencent/hy3-paid
ccg/tencent/hy4-preview
ccg/xai/grok-4.5
ccg/xai/grok-4.6
ccg/xai/grok-4.7
ccg/xiaomi/mimo-v2.5-pro
ccg/xiaomi/mimo-v2.6-flash
ccg/xiaomi/mimo-v2.6-pro
ccg/xiaomi/mimo-v2.6-pro-ultraspeed
ccg/z-ai/glm-5.3-flash
ccg/z-ai/glm-5.3-flashx
ccg/zai-org/GLM-5
ccg/zai-org/GLM-5.2
ccg/zai-org/GLM-5.2-Fast
ccg/zai-org/GLM-5.3

# DeepSeek 官方 (2)
ds/deepseek-flash
ds/deepseek-v4-pro

# 火山方舟 (14)
ark/deepseek-v4-1-flash-260910
ark/deepseek-v4-flash-ga-260731
ark/deepseek-v4-pro-ga-260813
ark/doubao-seed-2-0-code-preview-260215
ark/doubao-seed-2-0-lite-260428
ark/doubao-seed-2-0-mini-260428
ark/doubao-seed-2-1-lite-260915
ark/doubao-seed-2-1-pro-260628
ark/doubao-seed-2-1-pro-260915
ark/doubao-seed-2-1-turbo-260628
ark/doubao-seed-character-251128
ark/doubao-seed-character-260628
ark/glm-5-2-260617
ark/glm-5-3-flash-260828
```


### 机器可读版（models.json）

```json
{
  "_说明": "本机实测的可用模型清单。每台机器的账号权限可能不同，建议按 PROMPT 里的流程在本机复测。",
  "_生成自": "codeg-config / 服务器实测",
  "providers": {
    "ocg": {
      "name": "OpenCode Go",
      "upstream": "https://opencode.ai/zen/go/v1",
      "needs_session_header": true,
      "note": "上游要求 x-opencode-session 头，代理必须注入",
      "chat": [
        {
          "id": "deepseek-flash",
          "contextWindow": 1000000,
          "maxTokens": 384000
        },
        {
          "id": "deepseek-v4-flash",
          "contextWindow": 1000000,
          "maxTokens": 384000
        },
        {
          "id": "deepseek-v4-flash-vision-exp",
          "contextWindow": 1000000,
          "maxTokens": 384000
        },
        {
          "id": "deepseek-v4-pro",
          "contextWindow": 1000000,
          "maxTokens": 384000
        },
        {
          "id": "deepseek-v4.1-flash",
          "contextWindow": 1000000,
          "maxTokens": 384000
        },
        {
          "id": "glm-5.1",
          "contextWindow": 262144,
          "maxTokens": 131072
        },
        {
          "id": "glm-5.2",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "glm-5.3",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "glm-5.3-flash",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "hy3",
          "contextWindow": 256000,
          "maxTokens": 128000
        },
        {
          "id": "hy4-preview",
          "contextWindow": 1024000,
          "maxTokens": 64000
        },
        {
          "id": "kimi-k2.6",
          "contextWindow": 262144,
          "maxTokens": 65536
        },
        {
          "id": "kimi-k2.7-code",
          "contextWindow": 262144,
          "maxTokens": 262144
        },
        {
          "id": "kimi-k3",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        {
          "id": "longcat-2.0",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "longcat-2.5-preview-free",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "mimo-v2.5",
          "contextWindow": 1000000,
          "maxTokens": 128000
        },
        {
          "id": "mimo-v2.5-pro",
          "contextWindow": 1048576,
          "maxTokens": 128000
        },
        {
          "id": "mimo-v2.6-flash",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        {
          "id": "mimo-v2.6-pro",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        {
          "id": "minimax-m2.5",
          "contextWindow": 262144,
          "maxTokens": 131072
        },
        {
          "id": "minimax-m3",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "omen-alpha",
          "contextWindow": 262144,
          "maxTokens": 131072
        },
        {
          "id": "qwen3.6-plus",
          "contextWindow": 1000000,
          "maxTokens": 65536
        },
        {
          "id": "qwen3.7-max",
          "contextWindow": 1000000,
          "maxTokens": 65536
        },
        {
          "id": "qwen3.7-plus",
          "contextWindow": 1000000,
          "maxTokens": 65536
        },
        {
          "id": "qwen3.8-flash",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "qwen3.8-max",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "space-bunny",
          "contextWindow": 1048576,
          "maxTokens": 524288
        },
        {
          "id": "step-5-preview-free",
          "contextWindow": 1000000,
          "maxTokens": 131072
        }
      ],
      "responses": [
        "deepseek-flash",
        "deepseek-v4-flash",
        "deepseek-v4-flash-vision-exp",
        "deepseek-v4-pro",
        "deepseek-v4.1-flash",
        "gpt-5.6-luna",
        "gpt-6-luna",
        "grok-4.6",
        "grok-4.7",
        "muse-spark-1.2-contributor",
        "muse-spark-1.3-contributor"
      ],
      "responses_only": [
        "gpt-5.6-luna",
        "gpt-6-luna",
        "grok-4.6",
        "grok-4.7",
        "muse-spark-1.2-contributor",
        "muse-spark-1.3-contributor"
      ],
      "default": "longcat-2.5-preview-free"
    },
    "ccg": {
      "name": "Command Code GOAT",
      "upstream": "https://api.commandcode.ai/provider/v1",
      "note": "/messages 不接受 messages 数组里的 role:system，需提到顶层 system",
      "chat": [
        {
          "id": "MiniMaxAI/MiniMax-M2.5",
          "contextWindow": 200000,
          "maxTokens": 131072
        },
        {
          "id": "MiniMaxAI/MiniMax-M3",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "Qwen/Qwen3.6-Max-Preview",
          "contextWindow": 200000,
          "maxTokens": 131072
        },
        {
          "id": "Qwen/Qwen3.6-Plus",
          "contextWindow": 200000,
          "maxTokens": 131072
        },
        {
          "id": "Qwen/Qwen3.7-Flash",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "Qwen/Qwen3.7-Max",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "Qwen/Qwen3.7-Plus",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "Qwen/Qwen3.8-27B",
          "contextWindow": 262144,
          "maxTokens": 131072
        },
        {
          "id": "Qwen/Qwen3.8-Flash",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "Qwen/Qwen3.8-Max",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "Qwen/Qwen3.8-Max-0902",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "Qwen/Qwen3.8-Omni-Flash",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "deepseek/deepseek-v4-flash",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "deepseek/deepseek-v4-flash-fast",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "deepseek/deepseek-v4-flash-vision-exp",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "deepseek/deepseek-v4-pro",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "deepseek/deepseek-v4.1-flash",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "deepseek/deepseek-v4.1-flash-fast",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "google/gemini-3.7-flash",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        {
          "id": "google/gemini-3.8-flash",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "gpt-5.6-luna",
          "contextWindow": 1050000,
          "maxTokens": 131072
        },
        {
          "id": "gpt-5.6-sol",
          "contextWindow": 1050000,
          "maxTokens": 131072
        },
        {
          "id": "gpt-6-luna",
          "contextWindow": 1050000,
          "maxTokens": 131072
        },
        {
          "id": "inclusionai/ling-3.1-flash:free",
          "contextWindow": 262144,
          "maxTokens": 131072
        },
        {
          "id": "meituan/LongCat-2.0",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        {
          "id": "meta/muse-spark-1.2",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        {
          "id": "meta/muse-spark-1.2-contributor",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        {
          "id": "meta/muse-spark-1.3",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        {
          "id": "meta/muse-spark-1.3-contributor",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        {
          "id": "mistral/mistral-large-4",
          "contextWindow": 524288,
          "maxTokens": 131072
        },
        {
          "id": "moonshotai/Kimi-K2.5",
          "contextWindow": 256000,
          "maxTokens": 131072
        },
        {
          "id": "moonshotai/Kimi-K2.6",
          "contextWindow": 256000,
          "maxTokens": 131072
        },
        {
          "id": "moonshotai/Kimi-K2.7-Code",
          "contextWindow": 256000,
          "maxTokens": 131072
        },
        {
          "id": "moonshotai/Kimi-K2.7-Code-Highspeed",
          "contextWindow": 262000,
          "maxTokens": 131072
        },
        {
          "id": "moonshotai/Kimi-K3",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "nvidia/nemotron-3-ultra-550b-a55b",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "stealth/glyph-cluster:free",
          "contextWindow": 256000,
          "maxTokens": 131072
        },
        {
          "id": "stepfun/Step-3.7-Flash",
          "contextWindow": 256000,
          "maxTokens": 131072
        },
        {
          "id": "stepfun/Step-5-Preview",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "tencent/hy3-paid",
          "contextWindow": 262144,
          "maxTokens": 131072
        },
        {
          "id": "tencent/hy4-preview",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        {
          "id": "xai/grok-4.5",
          "contextWindow": 500000,
          "maxTokens": 131072
        },
        {
          "id": "xai/grok-4.6",
          "contextWindow": 500000,
          "maxTokens": 131072
        },
        {
          "id": "xai/grok-4.7",
          "contextWindow": 500000,
          "maxTokens": 131072
        },
        {
          "id": "xiaomi/mimo-v2.5-pro",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "xiaomi/mimo-v2.6-flash",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        {
          "id": "xiaomi/mimo-v2.6-pro",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        {
          "id": "xiaomi/mimo-v2.6-pro-ultraspeed",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        {
          "id": "z-ai/glm-5.3-flash",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        {
          "id": "z-ai/glm-5.3-flashx",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "zai-org/GLM-5",
          "contextWindow": 200000,
          "maxTokens": 131072
        },
        {
          "id": "zai-org/GLM-5.2",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "zai-org/GLM-5.2-Fast",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        {
          "id": "zai-org/GLM-5.3",
          "contextWindow": 1000000,
          "maxTokens": 131072
        }
      ],
      "responses": [
        "MiniMaxAI/MiniMax-M2.5",
        "MiniMaxAI/MiniMax-M3",
        "Qwen/Qwen3.6-Max-Preview",
        "Qwen/Qwen3.6-Plus",
        "Qwen/Qwen3.7-Flash",
        "Qwen/Qwen3.7-Max",
        "Qwen/Qwen3.7-Plus",
        "Qwen/Qwen3.8-27B",
        "Qwen/Qwen3.8-Max",
        "Qwen/Qwen3.8-Omni-Flash",
        "deepseek/deepseek-v4-flash",
        "deepseek/deepseek-v4-flash-vision-exp",
        "deepseek/deepseek-v4-pro",
        "deepseek/deepseek-v4.1-flash",
        "deepseek/deepseek-v4.1-flash-fast",
        "google/gemini-3.8-flash",
        "gpt-5.6-luna",
        "gpt-5.6-sol",
        "gpt-6-luna",
        "meta/muse-spark-1.2",
        "meta/muse-spark-1.2-contributor",
        "meta/muse-spark-1.3",
        "meta/muse-spark-1.3-contributor",
        "mistral/mistral-large-4",
        "moonshotai/Kimi-K2.5",
        "moonshotai/Kimi-K2.6",
        "moonshotai/Kimi-K2.7-Code",
        "moonshotai/Kimi-K2.7-Code-Highspeed",
        "moonshotai/Kimi-K3",
        "nvidia/nemotron-3-ultra-550b-a55b",
        "stealth/glyph-cluster:free",
        "stepfun/Step-3.7-Flash",
        "stepfun/Step-5-Preview",
        "tencent/hy3-paid",
        "xai/grok-4.5",
        "xai/grok-4.6",
        "xai/grok-4.7",
        "xiaomi/mimo-v2.5-pro",
        "xiaomi/mimo-v2.6-flash",
        "xiaomi/mimo-v2.6-pro",
        "xiaomi/mimo-v2.6-pro-ultraspeed",
        "z-ai/glm-5.3-flash",
        "z-ai/glm-5.3-flashx",
        "zai-org/GLM-5",
        "zai-org/GLM-5.2",
        "zai-org/GLM-5.2-Fast",
        "zai-org/GLM-5.3"
      ],
      "messages": [
        "claude-sonnet-5-5"
      ],
      "default": "stealth/glyph-cluster:free"
    },
    "ds": {
      "name": "DeepSeek Official",
      "upstream": "https://api.deepseek.com/v1",
      "note": "拒绝 role:developer，需改写成 system",
      "chat": [
        {
          "id": "deepseek-flash",
          "contextWindow": 1048576,
          "maxTokens": 393216
        },
        {
          "id": "deepseek-v4-pro",
          "contextWindow": 1048576,
          "maxTokens": 131072
        }
      ],
      "responses": [
        "deepseek-flash",
        "deepseek-v4-pro"
      ],
      "default": "deepseek-flash"
    },
    "ark": {
      "name": "Volcengine Ark",
      "upstream": "https://ark.cn-beijing.volces.com/api/v3",
      "note": "模型名必须带日期后缀；拒绝 role:developer",
      "chat": [
        {
          "id": "deepseek-v4-1-flash-260910",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        {
          "id": "deepseek-v4-flash-ga-260731",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        {
          "id": "deepseek-v4-pro-ga-260813",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        {
          "id": "doubao-seed-2-0-code-preview-260215",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        {
          "id": "doubao-seed-2-0-lite-260428",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        {
          "id": "doubao-seed-2-0-mini-260428",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        {
          "id": "doubao-seed-2-1-lite-260915",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        {
          "id": "doubao-seed-2-1-pro-260628",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        {
          "id": "doubao-seed-2-1-pro-260915",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        {
          "id": "doubao-seed-2-1-turbo-260628",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        {
          "id": "doubao-seed-character-251128",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        {
          "id": "doubao-seed-character-260628",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        {
          "id": "glm-5-2-260617",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        {
          "id": "glm-5-3-flash-260828",
          "contextWindow": 262144,
          "maxTokens": 32768
        }
      ],
      "responses": [
        "deepseek-v4-1-flash-260910",
        "deepseek-v4-flash-ga-260731",
        "deepseek-v4-pro-ga-260813",
        "doubao-seed-2-0-code-preview-260215",
        "doubao-seed-2-0-lite-260428",
        "doubao-seed-2-0-mini-260428",
        "doubao-seed-2-1-lite-260915",
        "doubao-seed-2-1-pro-260628",
        "doubao-seed-2-1-pro-260915",
        "doubao-seed-2-1-turbo-260628",
        "doubao-seed-character-251128",
        "doubao-seed-character-260628",
        "glm-5-2-260617",
        "glm-5-3-flash-260828"
      ],
      "default": "doubao-seed-2-1-pro-260915"
    }
  }
}
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
| `pi` | `%USERPROFILE%\.pi\agent\models.json` | 定义 provider `ocg`/`ccg`/`ds`/`ark`；`models` 是**数组** |
| `opencode` | `%USERPROFILE%\.config\opencode\opencode.jsonc` | `provider.<id>.models`；加 `"disabled_providers":["opencode-go"]` |
| `kimi_code` | `%USERPROFILE%\.kimi-code\config.toml` | 模型段自带 `model` 字段 |
| `hermes` | `%USERPROFILE%\.hermes\config.yaml` | `custom_providers`，靠 **name 转 slug** |
| `code_buddy` | `%USERPROFILE%\.codebuddy\models.json` | 配合 env `CODEBUDDY_*` |
| `open_claw` | `%USERPROFILE%\.openclaw\openclaw.json` | `models.providers` + allowlist |
| `cline` | `%USERPROFILE%\.cline\data\settings\` | **两个文件**，见坑 |
| `dsh` | `%USERPROFILE%\.dsh\settings.yaml` | |
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


### pi — %USERPROFILE%\.pi\agent\models.json

```json
{
  "providers": {
    "ocg": {
      "name": "OpenCode Go",
      "baseUrl": "http://127.0.0.1:8899/v1",
      "apiKey": "local",
      "api": "openai-completions",
      "models": [
        {
          "id": "deepseek-flash",
          "name": "OCG deepseek-flash",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 384000,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "deepseek-v4-flash",
          "name": "OCG DeepSeek V4 Flash",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 384000,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "deepseek-v4-flash-vision-exp",
          "name": "OCG DeepSeek V4 Flash Vision Exp",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 384000,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "deepseek-v4-pro",
          "name": "OCG DeepSeek V4 Pro (New)",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 384000,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "deepseek-v4.1-flash",
          "name": "OCG DeepSeek V4.1 Flash",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 384000,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "glm-5.1",
          "name": "OCG glm-5.1",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 200000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "glm-5.2",
          "name": "OCG GLM-5.2",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "glm-5.3",
          "name": "OCG GLM-5.3",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "glm-5.3-flash",
          "name": "OCG GLM-5.3-Flash",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "hy3",
          "name": "OCG Hy3",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 256000,
          "maxTokens": 128000,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "hy4-preview",
          "name": "OCG Hy4 preview",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1024000,
          "maxTokens": 64000,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "kimi-k2.6",
          "name": "OCG Kimi K2.6",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262144,
          "maxTokens": 65536,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "kimi-k2.7-code",
          "name": "OCG Kimi K2.7 Code",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262144,
          "maxTokens": 262144,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "kimi-k3",
          "name": "OCG Kimi K3",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1048576,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "longcat-2.0",
          "name": "OCG LongCat-2.0",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "longcat-2.5-preview-free",
          "name": "OCG LongCat 2.5 Preview Free",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "mimo-v2.5",
          "name": "OCG MiMo V2.5",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 128000,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "mimo-v2.5-pro",
          "name": "OCG MiMo V2.5 Pro",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1048576,
          "maxTokens": 128000,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "mimo-v2.6-flash",
          "name": "OCG MiMo-V2.6-Flash",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1048576,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "mimo-v2.6-pro",
          "name": "OCG MiMo-V2.6-Pro",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1048576,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "minimax-m2.5",
          "name": "OCG minimax-m2.5",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 200000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "minimax-m3",
          "name": "OCG MiniMax-M3",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "omen-alpha",
          "name": "OCG omen-alpha",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262144,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "qwen3.6-plus",
          "name": "OCG Qwen3.6 Plus",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 65536,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "qwen3.7-max",
          "name": "OCG Qwen3.7 Max",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 65536,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "qwen3.7-plus",
          "name": "OCG Qwen3.7 Plus",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 65536,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "qwen3.8-flash",
          "name": "OCG Qwen3.8 Flash",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "qwen3.8-max",
          "name": "OCG Qwen3.8 Max",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "space-bunny",
          "name": "OCG Space Bunny",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1048576,
          "maxTokens": 524288,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "step-5-preview-free",
          "name": "OCG step-5-preview-free",
          "provider": "ocg",
          "baseUrl": "http://127.0.0.1:8899/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        }
      ]
    },
    "ccg": {
      "name": "Command Code GOAT",
      "baseUrl": "https://api.commandcode.ai/provider/v1",
      "apiKey": "${COMMANDCODE_API_KEY}",
      "api": "openai-completions",
      "models": [
        {
          "id": "MiniMaxAI/MiniMax-M2.5",
          "name": "CCG MiniMax M2.5",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 200000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "MiniMaxAI/MiniMax-M3",
          "name": "CCG MiniMax M3",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "Qwen/Qwen3.6-Max-Preview",
          "name": "CCG Qwen 3.6 Max Preview",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 200000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "Qwen/Qwen3.6-Plus",
          "name": "CCG Qwen 3.6 Plus",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 200000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "Qwen/Qwen3.7-Flash",
          "name": "CCG Qwen 3.7 Flash",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "Qwen/Qwen3.7-Max",
          "name": "CCG Qwen 3.7 Max",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "Qwen/Qwen3.7-Plus",
          "name": "CCG Qwen 3.7 Plus",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "Qwen/Qwen3.8-27B",
          "name": "CCG Qwen 3.8 27B",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262144,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "Qwen/Qwen3.8-Flash",
          "name": "CCG Qwen 3.8 Flash",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "Qwen/Qwen3.8-Max",
          "name": "CCG Qwen 3.8 Max",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "Qwen/Qwen3.8-Max-0902",
          "name": "CCG Qwen 3.8 Max 0902",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "Qwen/Qwen3.8-Omni-Flash",
          "name": "CCG Qwen 3.8 Omni Flash",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "deepseek/deepseek-v4-flash",
          "name": "CCG DeepSeek V4 Flash (latest)",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "deepseek/deepseek-v4-flash-fast",
          "name": "CCG DeepSeek V4 Flash Fast",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "deepseek/deepseek-v4-flash-vision-exp",
          "name": "CCG DeepSeek V4 Flash Vision (exp)",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "deepseek/deepseek-v4-pro",
          "name": "CCG DeepSeek V4 Pro (latest)",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "deepseek/deepseek-v4.1-flash",
          "name": "CCG DeepSeek V4.1 Flash",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "deepseek/deepseek-v4.1-flash-fast",
          "name": "CCG DeepSeek V4.1 Flash Fast",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "google/gemini-3.7-flash",
          "name": "CCG Gemini 3.7 Flash",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1048576,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "google/gemini-3.8-flash",
          "name": "CCG Gemini 3.8 Flash",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "gpt-5.6-luna",
          "name": "CCG GPT-5.6 Luna",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1050000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "gpt-5.6-sol",
          "name": "CCG GPT-5.6 Sol",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1050000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "gpt-6-luna",
          "name": "CCG GPT-6 Luna",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1050000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "inclusionai/ling-3.1-flash:free",
          "name": "CCG Ling 3.1 Flash",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262144,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "meituan/LongCat-2.0",
          "name": "CCG LongCat 2.0",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1048576,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "meta/muse-spark-1.2",
          "name": "CCG Muse Spark 1.2",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1048576,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "meta/muse-spark-1.2-contributor",
          "name": "CCG Muse Spark 1.2 Contributor",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1048576,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "meta/muse-spark-1.3",
          "name": "CCG Muse Spark 1.3",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1048576,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "meta/muse-spark-1.3-contributor",
          "name": "CCG Muse Spark 1.3 Contributor",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1048576,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "mistral/mistral-large-4",
          "name": "CCG Mistral Large 4",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 524288,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "moonshotai/Kimi-K2.5",
          "name": "CCG Kimi K2.5",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 256000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "moonshotai/Kimi-K2.6",
          "name": "CCG Kimi K2.6",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 256000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "moonshotai/Kimi-K2.7-Code",
          "name": "CCG Kimi K2.7 Code",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 256000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "moonshotai/Kimi-K2.7-Code-Highspeed",
          "name": "CCG Kimi K2.7 Code HighSpeed",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "moonshotai/Kimi-K3",
          "name": "CCG Kimi K3",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "nvidia/nemotron-3-ultra-550b-a55b",
          "name": "CCG Nemotron 3 Ultra",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "stealth/glyph-cluster:free",
          "name": "CCG Glyph Cluster",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 256000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "stepfun/Step-3.7-Flash",
          "name": "CCG Step 3.7 Flash",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 256000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "stepfun/Step-5-Preview",
          "name": "CCG Step 5 Preview",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "tencent/hy3-paid",
          "name": "CCG Tencent Hy3",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262144,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "tencent/hy4-preview",
          "name": "CCG Tencent Hy4 Preview",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1048576,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "xai/grok-4.5",
          "name": "CCG Grok 4.5",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 500000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "xai/grok-4.6",
          "name": "CCG Grok 4.6",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 500000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "xai/grok-4.7",
          "name": "CCG Grok 4.7",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 500000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "xiaomi/mimo-v2.5-pro",
          "name": "CCG MiMo V2.5 Pro",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "xiaomi/mimo-v2.6-flash",
          "name": "CCG MiMo V2.6 Flash",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1048576,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "xiaomi/mimo-v2.6-pro",
          "name": "CCG MiMo V2.6 Pro",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1048576,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "xiaomi/mimo-v2.6-pro-ultraspeed",
          "name": "CCG MiMo V2.6 Pro UltraSpeed",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1048576,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "z-ai/glm-5.3-flash",
          "name": "CCG GLM-5.3 Flash",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1048576,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "z-ai/glm-5.3-flashx",
          "name": "CCG GLM-5.3 FlashX",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "zai-org/GLM-5",
          "name": "CCG GLM-5",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 200000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "zai-org/GLM-5.2",
          "name": "CCG GLM-5.2",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "zai-org/GLM-5.2-Fast",
          "name": "CCG GLM-5.2 Fast",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "zai-org/GLM-5.3",
          "name": "CCG GLM-5.3",
          "provider": "ccg",
          "baseUrl": "https://api.commandcode.ai/provider/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1000000,
          "maxTokens": 131072,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        }
      ]
    },
    "ds": {
      "name": "DeepSeek Official",
      "baseUrl": "http://127.0.0.1:8896/v1",
      "apiKey": "local",
      "api": "openai-completions",
      "models": [
        {
          "id": "deepseek-flash",
          "name": "DS DeepSeek-V4.1-Flash",
          "provider": "ds",
          "baseUrl": "http://127.0.0.1:8896/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 1048576,
          "maxTokens": 393216,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "deepseek-v4-pro",
          "name": "DS DeepSeek-V4-Pro",
          "provider": "ds",
          "baseUrl": "http://127.0.0.1:8896/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text"
          ],
          "contextWindow": 1048576,
          "maxTokens": 393216,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        }
      ]
    },
    "ark": {
      "name": "Volcengine Ark",
      "baseUrl": "http://127.0.0.1:8897/v1",
      "apiKey": "local",
      "api": "openai-completions",
      "models": [
        {
          "id": "deepseek-v4-1-flash-260910",
          "name": "ARK deepseek-v4-1-flash-260910",
          "provider": "ark",
          "baseUrl": "http://127.0.0.1:8897/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262144,
          "maxTokens": 32768,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "deepseek-v4-flash-ga-260731",
          "name": "ARK deepseek-v4-flash-ga-260731",
          "provider": "ark",
          "baseUrl": "http://127.0.0.1:8897/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262144,
          "maxTokens": 32768,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "deepseek-v4-pro-ga-260813",
          "name": "ARK deepseek-v4-pro-ga-260813",
          "provider": "ark",
          "baseUrl": "http://127.0.0.1:8897/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262144,
          "maxTokens": 32768,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "doubao-seed-2-0-code-preview-260215",
          "name": "ARK doubao-seed-2-0-code-preview-260215",
          "provider": "ark",
          "baseUrl": "http://127.0.0.1:8897/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262144,
          "maxTokens": 32768,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "doubao-seed-2-0-lite-260428",
          "name": "ARK doubao-seed-2-0-lite-260428",
          "provider": "ark",
          "baseUrl": "http://127.0.0.1:8897/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262144,
          "maxTokens": 32768,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "doubao-seed-2-0-mini-260428",
          "name": "ARK doubao-seed-2-0-mini-260428",
          "provider": "ark",
          "baseUrl": "http://127.0.0.1:8897/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262144,
          "maxTokens": 32768,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "doubao-seed-2-1-lite-260915",
          "name": "ARK doubao-seed-2-1-lite-260915",
          "provider": "ark",
          "baseUrl": "http://127.0.0.1:8897/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262144,
          "maxTokens": 32768,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "doubao-seed-2-1-pro-260628",
          "name": "ARK doubao-seed-2-1-pro-260628",
          "provider": "ark",
          "baseUrl": "http://127.0.0.1:8897/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262144,
          "maxTokens": 32768,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "doubao-seed-2-1-pro-260915",
          "name": "ARK doubao-seed-2-1-pro-260915",
          "provider": "ark",
          "baseUrl": "http://127.0.0.1:8897/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262144,
          "maxTokens": 32768,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "doubao-seed-2-1-turbo-260628",
          "name": "ARK doubao-seed-2-1-turbo-260628",
          "provider": "ark",
          "baseUrl": "http://127.0.0.1:8897/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262144,
          "maxTokens": 32768,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "doubao-seed-character-251128",
          "name": "ARK doubao-seed-character-251128",
          "provider": "ark",
          "baseUrl": "http://127.0.0.1:8897/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262144,
          "maxTokens": 32768,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "doubao-seed-character-260628",
          "name": "ARK doubao-seed-character-260628",
          "provider": "ark",
          "baseUrl": "http://127.0.0.1:8897/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262144,
          "maxTokens": 32768,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "glm-5-2-260617",
          "name": "ARK glm-5-2-260617",
          "provider": "ark",
          "baseUrl": "http://127.0.0.1:8897/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262144,
          "maxTokens": 32768,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        },
        {
          "id": "glm-5-3-flash-260828",
          "name": "ARK glm-5-3-flash-260828",
          "provider": "ark",
          "baseUrl": "http://127.0.0.1:8897/v1",
          "api": "openai-completions",
          "reasoning": true,
          "input": [
            "text",
            "image"
          ],
          "contextWindow": 262144,
          "maxTokens": 32768,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        }
      ]
    }
  }
}
```


### kimi — %USERPROFILE%\.kimi-code\config.toml

```toml
default_model = "ocg/longcat-2.5-preview-free"
default_provider = "opencode-go"

[providers.opencode-go]
type = "openai"
base_url = "http://127.0.0.1:8899/v1"
api_key = "local"
default_model = "longcat-2.5-preview-free"

[providers.commandcode]
type = "openai"
base_url = "https://api.commandcode.ai/provider/v1"
api_key = "${COMMANDCODE_API_KEY}"
default_model = "stealth/glyph-cluster:free"

[providers.deepseek]
type = "openai"
base_url = "http://127.0.0.1:8896/v1"
api_key = "local"
default_model = "deepseek-flash"

[providers.ark]
type = "openai"
base_url = "http://127.0.0.1:8897/v1"
api_key = "local"
default_model = "deepseek-v4-1-flash-260910"

[models."ocg/deepseek-flash"]
provider = "opencode-go"
model = "deepseek-flash"
max_context_size = 1000000

[models."ocg/deepseek-v4-flash"]
provider = "opencode-go"
model = "deepseek-v4-flash"
max_context_size = 1000000

[models."ocg/deepseek-v4-flash-vision-exp"]
provider = "opencode-go"
model = "deepseek-v4-flash-vision-exp"
max_context_size = 1000000

[models."ocg/deepseek-v4-pro"]
provider = "opencode-go"
model = "deepseek-v4-pro"
max_context_size = 1000000

[models."ocg/deepseek-v4.1-flash"]
provider = "opencode-go"
model = "deepseek-v4.1-flash"
max_context_size = 1000000

[models."ocg/glm-5.1"]
provider = "opencode-go"
model = "glm-5.1"
max_context_size = 200000

[models."ocg/glm-5.2"]
provider = "opencode-go"
model = "glm-5.2"
max_context_size = 1000000

[models."ocg/glm-5.3"]
provider = "opencode-go"
model = "glm-5.3"
max_context_size = 1000000

[models."ocg/glm-5.3-flash"]
provider = "opencode-go"
model = "glm-5.3-flash"
max_context_size = 1000000

[models."ocg/hy3"]
provider = "opencode-go"
model = "hy3"
max_context_size = 256000

[models."ocg/hy4-preview"]
provider = "opencode-go"
model = "hy4-preview"
max_context_size = 1024000

[models."ocg/kimi-k2.6"]
provider = "opencode-go"
model = "kimi-k2.6"
max_context_size = 262144

[models."ocg/kimi-k2.7-code"]
provider = "opencode-go"
model = "kimi-k2.7-code"
max_context_size = 262144

[models."ocg/kimi-k3"]
provider = "opencode-go"
model = "kimi-k3"
max_context_size = 1048576

[models."ocg/longcat-2.0"]
provider = "opencode-go"
model = "longcat-2.0"
max_context_size = 1000000

[models."ocg/longcat-2.5-preview-free"]
provider = "opencode-go"
model = "longcat-2.5-preview-free"
max_context_size = 1000000

[models."ocg/mimo-v2.5"]
provider = "opencode-go"
model = "mimo-v2.5"
max_context_size = 1000000

[models."ocg/mimo-v2.5-pro"]
provider = "opencode-go"
model = "mimo-v2.5-pro"
max_context_size = 1048576

[models."ocg/mimo-v2.6-flash"]
provider = "opencode-go"
model = "mimo-v2.6-flash"
max_context_size = 1048576

[models."ocg/mimo-v2.6-pro"]
provider = "opencode-go"
model = "mimo-v2.6-pro"
max_context_size = 1048576

[models."ocg/minimax-m2.5"]
provider = "opencode-go"
model = "minimax-m2.5"
max_context_size = 200000

[models."ocg/minimax-m3"]
provider = "opencode-go"
model = "minimax-m3"
max_context_size = 1000000

[models."ocg/omen-alpha"]
provider = "opencode-go"
model = "omen-alpha"
max_context_size = 262144

[models."ocg/qwen3.6-plus"]
provider = "opencode-go"
model = "qwen3.6-plus"
max_context_size = 1000000

[models."ocg/qwen3.7-max"]
provider = "opencode-go"
model = "qwen3.7-max"
max_context_size = 1000000

[models."ocg/qwen3.7-plus"]
provider = "opencode-go"
model = "qwen3.7-plus"
max_context_size = 1000000

[models."ocg/qwen3.8-flash"]
provider = "opencode-go"
model = "qwen3.8-flash"
max_context_size = 1000000

[models."ocg/qwen3.8-max"]
provider = "opencode-go"
model = "qwen3.8-max"
max_context_size = 1000000

[models."ocg/space-bunny"]
provider = "opencode-go"
model = "space-bunny"
max_context_size = 1048576

[models."ocg/step-5-preview-free"]
provider = "opencode-go"
model = "step-5-preview-free"
max_context_size = 1000000

[models."ccg/MiniMaxAI/MiniMax-M2.5"]
provider = "commandcode"
model = "MiniMaxAI/MiniMax-M2.5"
max_context_size = 200000

[models."ccg/MiniMaxAI/MiniMax-M3"]
provider = "commandcode"
model = "MiniMaxAI/MiniMax-M3"
max_context_size = 1000000

[models."ccg/Qwen/Qwen3.6-Max-Preview"]
provider = "commandcode"
model = "Qwen/Qwen3.6-Max-Preview"
max_context_size = 200000

[models."ccg/Qwen/Qwen3.6-Plus"]
provider = "commandcode"
model = "Qwen/Qwen3.6-Plus"
max_context_size = 200000

[models."ccg/Qwen/Qwen3.7-Flash"]
provider = "commandcode"
model = "Qwen/Qwen3.7-Flash"
max_context_size = 1000000

[models."ccg/Qwen/Qwen3.7-Max"]
provider = "commandcode"
model = "Qwen/Qwen3.7-Max"
max_context_size = 1000000

[models."ccg/Qwen/Qwen3.7-Plus"]
provider = "commandcode"
model = "Qwen/Qwen3.7-Plus"
max_context_size = 1000000

[models."ccg/Qwen/Qwen3.8-27B"]
provider = "commandcode"
model = "Qwen/Qwen3.8-27B"
max_context_size = 262144

[models."ccg/Qwen/Qwen3.8-Flash"]
provider = "commandcode"
model = "Qwen/Qwen3.8-Flash"
max_context_size = 1000000

[models."ccg/Qwen/Qwen3.8-Max"]
provider = "commandcode"
model = "Qwen/Qwen3.8-Max"
max_context_size = 1000000

[models."ccg/Qwen/Qwen3.8-Max-0902"]
provider = "commandcode"
model = "Qwen/Qwen3.8-Max-0902"
max_context_size = 1000000

[models."ccg/Qwen/Qwen3.8-Omni-Flash"]
provider = "commandcode"
model = "Qwen/Qwen3.8-Omni-Flash"
max_context_size = 1000000

[models."ccg/deepseek/deepseek-v4-flash"]
provider = "commandcode"
model = "deepseek/deepseek-v4-flash"
max_context_size = 1000000

[models."ccg/deepseek/deepseek-v4-flash-fast"]
provider = "commandcode"
model = "deepseek/deepseek-v4-flash-fast"
max_context_size = 1000000

[models."ccg/deepseek/deepseek-v4-flash-vision-exp"]
provider = "commandcode"
model = "deepseek/deepseek-v4-flash-vision-exp"
max_context_size = 1000000

[models."ccg/deepseek/deepseek-v4-pro"]
provider = "commandcode"
model = "deepseek/deepseek-v4-pro"
max_context_size = 1000000

[models."ccg/deepseek/deepseek-v4.1-flash"]
provider = "commandcode"
model = "deepseek/deepseek-v4.1-flash"
max_context_size = 1000000

[models."ccg/deepseek/deepseek-v4.1-flash-fast"]
provider = "commandcode"
model = "deepseek/deepseek-v4.1-flash-fast"
max_context_size = 1000000

[models."ccg/google/gemini-3.7-flash"]
provider = "commandcode"
model = "google/gemini-3.7-flash"
max_context_size = 1048576

[models."ccg/google/gemini-3.8-flash"]
provider = "commandcode"
model = "google/gemini-3.8-flash"
max_context_size = 1000000

[models."ccg/gpt-5.6-luna"]
provider = "commandcode"
model = "gpt-5.6-luna"
max_context_size = 1050000

[models."ccg/gpt-5.6-sol"]
provider = "commandcode"
model = "gpt-5.6-sol"
max_context_size = 1050000

[models."ccg/gpt-6-luna"]
provider = "commandcode"
model = "gpt-6-luna"
max_context_size = 1050000

[models."ccg/inclusionai/ling-3.1-flash:free"]
provider = "commandcode"
model = "inclusionai/ling-3.1-flash:free"
max_context_size = 262144

[models."ccg/meituan/LongCat-2.0"]
provider = "commandcode"
model = "meituan/LongCat-2.0"
max_context_size = 1048576

[models."ccg/meta/muse-spark-1.2"]
provider = "commandcode"
model = "meta/muse-spark-1.2"
max_context_size = 1048576

[models."ccg/meta/muse-spark-1.2-contributor"]
provider = "commandcode"
model = "meta/muse-spark-1.2-contributor"
max_context_size = 1048576

[models."ccg/meta/muse-spark-1.3"]
provider = "commandcode"
model = "meta/muse-spark-1.3"
max_context_size = 1048576

[models."ccg/meta/muse-spark-1.3-contributor"]
provider = "commandcode"
model = "meta/muse-spark-1.3-contributor"
max_context_size = 1048576

[models."ccg/mistral/mistral-large-4"]
provider = "commandcode"
model = "mistral/mistral-large-4"
max_context_size = 524288

[models."ccg/moonshotai/Kimi-K2.5"]
provider = "commandcode"
model = "moonshotai/Kimi-K2.5"
max_context_size = 256000

[models."ccg/moonshotai/Kimi-K2.6"]
provider = "commandcode"
model = "moonshotai/Kimi-K2.6"
max_context_size = 256000

[models."ccg/moonshotai/Kimi-K2.7-Code"]
provider = "commandcode"
model = "moonshotai/Kimi-K2.7-Code"
max_context_size = 256000

[models."ccg/moonshotai/Kimi-K2.7-Code-Highspeed"]
provider = "commandcode"
model = "moonshotai/Kimi-K2.7-Code-Highspeed"
max_context_size = 262000

[models."ccg/moonshotai/Kimi-K3"]
provider = "commandcode"
model = "moonshotai/Kimi-K3"
max_context_size = 1000000

[models."ccg/nvidia/nemotron-3-ultra-550b-a55b"]
provider = "commandcode"
model = "nvidia/nemotron-3-ultra-550b-a55b"
max_context_size = 1000000

[models."ccg/stealth/glyph-cluster:free"]
provider = "commandcode"
model = "stealth/glyph-cluster:free"
max_context_size = 256000

[models."ccg/stepfun/Step-3.7-Flash"]
provider = "commandcode"
model = "stepfun/Step-3.7-Flash"
max_context_size = 256000

[models."ccg/stepfun/Step-5-Preview"]
provider = "commandcode"
model = "stepfun/Step-5-Preview"
max_context_size = 1000000

[models."ccg/tencent/hy3-paid"]
provider = "commandcode"
model = "tencent/hy3-paid"
max_context_size = 262144

[models."ccg/tencent/hy4-preview"]
provider = "commandcode"
model = "tencent/hy4-preview"
max_context_size = 1048576

[models."ccg/xai/grok-4.5"]
provider = "commandcode"
model = "xai/grok-4.5"
max_context_size = 500000

[models."ccg/xai/grok-4.6"]
provider = "commandcode"
model = "xai/grok-4.6"
max_context_size = 500000

[models."ccg/xai/grok-4.7"]
provider = "commandcode"
model = "xai/grok-4.7"
max_context_size = 500000

[models."ccg/xiaomi/mimo-v2.5-pro"]
provider = "commandcode"
model = "xiaomi/mimo-v2.5-pro"
max_context_size = 1000000

[models."ccg/xiaomi/mimo-v2.6-flash"]
provider = "commandcode"
model = "xiaomi/mimo-v2.6-flash"
max_context_size = 1048576

[models."ccg/xiaomi/mimo-v2.6-pro"]
provider = "commandcode"
model = "xiaomi/mimo-v2.6-pro"
max_context_size = 1048576

[models."ccg/xiaomi/mimo-v2.6-pro-ultraspeed"]
provider = "commandcode"
model = "xiaomi/mimo-v2.6-pro-ultraspeed"
max_context_size = 1048576

[models."ccg/z-ai/glm-5.3-flash"]
provider = "commandcode"
model = "z-ai/glm-5.3-flash"
max_context_size = 1048576

[models."ccg/z-ai/glm-5.3-flashx"]
provider = "commandcode"
model = "z-ai/glm-5.3-flashx"
max_context_size = 1000000

[models."ccg/zai-org/GLM-5"]
provider = "commandcode"
model = "zai-org/GLM-5"
max_context_size = 200000

[models."ccg/zai-org/GLM-5.2"]
provider = "commandcode"
model = "zai-org/GLM-5.2"
max_context_size = 1000000

[models."ccg/zai-org/GLM-5.2-Fast"]
provider = "commandcode"
model = "zai-org/GLM-5.2-Fast"
max_context_size = 1000000

[models."ccg/zai-org/GLM-5.3"]
provider = "commandcode"
model = "zai-org/GLM-5.3"
max_context_size = 1000000

[models."ds/deepseek-flash"]
provider = "deepseek"
model = "deepseek-flash"
max_context_size = 1048576

[models."ds/deepseek-v4-pro"]
provider = "deepseek"
model = "deepseek-v4-pro"
max_context_size = 1048576

[models."ark/deepseek-v4-1-flash-260910"]
provider = "ark"
model = "deepseek-v4-1-flash-260910"
max_context_size = 262144

[models."ark/deepseek-v4-flash-ga-260731"]
provider = "ark"
model = "deepseek-v4-flash-ga-260731"
max_context_size = 262144

[models."ark/deepseek-v4-pro-ga-260813"]
provider = "ark"
model = "deepseek-v4-pro-ga-260813"
max_context_size = 262144

[models."ark/doubao-seed-2-0-code-preview-260215"]
provider = "ark"
model = "doubao-seed-2-0-code-preview-260215"
max_context_size = 262144

[models."ark/doubao-seed-2-0-lite-260428"]
provider = "ark"
model = "doubao-seed-2-0-lite-260428"
max_context_size = 262144

[models."ark/doubao-seed-2-0-mini-260428"]
provider = "ark"
model = "doubao-seed-2-0-mini-260428"
max_context_size = 262144

[models."ark/doubao-seed-2-1-lite-260915"]
provider = "ark"
model = "doubao-seed-2-1-lite-260915"
max_context_size = 262144

[models."ark/doubao-seed-2-1-pro-260628"]
provider = "ark"
model = "doubao-seed-2-1-pro-260628"
max_context_size = 262144

[models."ark/doubao-seed-2-1-pro-260915"]
provider = "ark"
model = "doubao-seed-2-1-pro-260915"
max_context_size = 262144

[models."ark/doubao-seed-2-1-turbo-260628"]
provider = "ark"
model = "doubao-seed-2-1-turbo-260628"
max_context_size = 262144

[models."ark/doubao-seed-character-251128"]
provider = "ark"
model = "doubao-seed-character-251128"
max_context_size = 262144

[models."ark/doubao-seed-character-260628"]
provider = "ark"
model = "doubao-seed-character-260628"
max_context_size = 262144

[models."ark/glm-5-2-260617"]
provider = "ark"
model = "glm-5-2-260617"
max_context_size = 262144

[models."ark/glm-5-3-flash-260828"]
provider = "ark"
model = "glm-5-3-flash-260828"
max_context_size = 262144
```


### hermes — %USERPROFILE%\.hermes\config.yaml

```yaml
provider: custom:ocg-longcat-2.5-preview-free
model: longcat-2.5-preview-free
custom_providers:
- name: OCG deepseek-flash
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: deepseek-flash
- name: OCG DeepSeek V4 Flash
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: deepseek-v4-flash
- name: OCG DeepSeek V4 Flash Vision Exp
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: deepseek-v4-flash-vision-exp
- name: OCG DeepSeek V4 Pro (New)
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: deepseek-v4-pro
- name: OCG DeepSeek V4.1 Flash
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: deepseek-v4.1-flash
- name: OCG glm-5.1
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: glm-5.1
- name: OCG GLM-5.2
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: glm-5.2
- name: OCG GLM-5.3
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: glm-5.3
- name: OCG GLM-5.3-Flash
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: glm-5.3-flash
- name: OCG Hy3
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: hy3
- name: OCG Hy4 preview
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: hy4-preview
- name: OCG Kimi K2.6
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: kimi-k2.6
- name: OCG Kimi K2.7 Code
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: kimi-k2.7-code
- name: OCG Kimi K3
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: kimi-k3
- name: OCG LongCat-2.0
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: longcat-2.0
- name: OCG LongCat 2.5 Preview Free
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: longcat-2.5-preview-free
- name: OCG MiMo V2.5
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: mimo-v2.5
- name: OCG MiMo V2.5 Pro
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: mimo-v2.5-pro
- name: OCG MiMo-V2.6-Flash
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: mimo-v2.6-flash
- name: OCG MiMo-V2.6-Pro
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: mimo-v2.6-pro
- name: OCG minimax-m2.5
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: minimax-m2.5
- name: OCG MiniMax-M3
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: minimax-m3
- name: OCG omen-alpha
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: omen-alpha
- name: OCG Qwen3.6 Plus
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: qwen3.6-plus
- name: OCG Qwen3.7 Max
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: qwen3.7-max
- name: OCG Qwen3.7 Plus
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: qwen3.7-plus
- name: OCG Qwen3.8 Flash
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: qwen3.8-flash
- name: OCG Qwen3.8 Max
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: qwen3.8-max
- name: OCG Space Bunny
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: space-bunny
- name: OCG step-5-preview-free
  base_url: http://127.0.0.1:8899/v1
  api_key: local
  model: step-5-preview-free
- name: CCG MiniMax M2.5
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: MiniMaxAI/MiniMax-M2.5
- name: CCG MiniMax M3
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: MiniMaxAI/MiniMax-M3
- name: CCG Qwen 3.6 Max Preview
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: Qwen/Qwen3.6-Max-Preview
- name: CCG Qwen 3.6 Plus
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: Qwen/Qwen3.6-Plus
- name: CCG Qwen 3.7 Flash
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: Qwen/Qwen3.7-Flash
- name: CCG Qwen 3.7 Max
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: Qwen/Qwen3.7-Max
- name: CCG Qwen 3.7 Plus
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: Qwen/Qwen3.7-Plus
- name: CCG Qwen 3.8 27B
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: Qwen/Qwen3.8-27B
- name: CCG Qwen 3.8 Flash
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: Qwen/Qwen3.8-Flash
- name: CCG Qwen 3.8 Max
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: Qwen/Qwen3.8-Max
- name: CCG Qwen 3.8 Max 0902
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: Qwen/Qwen3.8-Max-0902
- name: CCG Qwen 3.8 Omni Flash
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: Qwen/Qwen3.8-Omni-Flash
- name: CCG DeepSeek V4 Flash (latest)
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: deepseek/deepseek-v4-flash
- name: CCG DeepSeek V4 Flash Fast
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: deepseek/deepseek-v4-flash-fast
- name: CCG DeepSeek V4 Flash Vision (exp)
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: deepseek/deepseek-v4-flash-vision-exp
- name: CCG DeepSeek V4 Pro (latest)
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: deepseek/deepseek-v4-pro
- name: CCG DeepSeek V4.1 Flash
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: deepseek/deepseek-v4.1-flash
- name: CCG DeepSeek V4.1 Flash Fast
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: deepseek/deepseek-v4.1-flash-fast
- name: CCG Gemini 3.7 Flash
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: google/gemini-3.7-flash
- name: CCG Gemini 3.8 Flash
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: google/gemini-3.8-flash
- name: CCG GPT-5.6 Luna
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: gpt-5.6-luna
- name: CCG GPT-5.6 Sol
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: gpt-5.6-sol
- name: CCG GPT-6 Luna
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: gpt-6-luna
- name: CCG Ling 3.1 Flash
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: inclusionai/ling-3.1-flash:free
- name: CCG LongCat 2.0
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: meituan/LongCat-2.0
- name: CCG Muse Spark 1.2
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: meta/muse-spark-1.2
- name: CCG Muse Spark 1.2 Contributor
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: meta/muse-spark-1.2-contributor
- name: CCG Muse Spark 1.3
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: meta/muse-spark-1.3
- name: CCG Muse Spark 1.3 Contributor
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: meta/muse-spark-1.3-contributor
- name: CCG Mistral Large 4
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: mistral/mistral-large-4
- name: CCG Kimi K2.5
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: moonshotai/Kimi-K2.5
- name: CCG Kimi K2.6
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: moonshotai/Kimi-K2.6
- name: CCG Kimi K2.7 Code
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: moonshotai/Kimi-K2.7-Code
- name: CCG Kimi K2.7 Code HighSpeed
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: moonshotai/Kimi-K2.7-Code-Highspeed
- name: CCG Kimi K3
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: moonshotai/Kimi-K3
- name: CCG Nemotron 3 Ultra
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: nvidia/nemotron-3-ultra-550b-a55b
- name: CCG Glyph Cluster
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: stealth/glyph-cluster:free
- name: CCG Step 3.7 Flash
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: stepfun/Step-3.7-Flash
- name: CCG Step 5 Preview
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: stepfun/Step-5-Preview
- name: CCG Tencent Hy3
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: tencent/hy3-paid
- name: CCG Tencent Hy4 Preview
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: tencent/hy4-preview
- name: CCG Grok 4.5
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: xai/grok-4.5
- name: CCG Grok 4.6
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: xai/grok-4.6
- name: CCG Grok 4.7
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: xai/grok-4.7
- name: CCG MiMo V2.5 Pro
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: xiaomi/mimo-v2.5-pro
- name: CCG MiMo V2.6 Flash
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: xiaomi/mimo-v2.6-flash
- name: CCG MiMo V2.6 Pro
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: xiaomi/mimo-v2.6-pro
- name: CCG MiMo V2.6 Pro UltraSpeed
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: xiaomi/mimo-v2.6-pro-ultraspeed
- name: CCG GLM-5.3 Flash
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: z-ai/glm-5.3-flash
- name: CCG GLM-5.3 FlashX
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: z-ai/glm-5.3-flashx
- name: CCG GLM-5
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: zai-org/GLM-5
- name: CCG GLM-5.2
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: zai-org/GLM-5.2
- name: CCG GLM-5.2 Fast
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: zai-org/GLM-5.2-Fast
- name: CCG GLM-5.3
  base_url: https://api.commandcode.ai/provider/v1
  api_key: ${COMMANDCODE_API_KEY}
  model: zai-org/GLM-5.3
- name: DS deepseek-flash
  base_url: http://127.0.0.1:8896/v1
  api_key: local
  model: deepseek-flash
- name: DS deepseek-v4-pro
  base_url: http://127.0.0.1:8896/v1
  api_key: local
  model: deepseek-v4-pro
- name: ARK deepseek-v4-1-flash-260910
  base_url: http://127.0.0.1:8897/v1
  api_key: local
  model: deepseek-v4-1-flash-260910
- name: ARK deepseek-v4-flash-ga-260731
  base_url: http://127.0.0.1:8897/v1
  api_key: local
  model: deepseek-v4-flash-ga-260731
- name: ARK deepseek-v4-pro-ga-260813
  base_url: http://127.0.0.1:8897/v1
  api_key: local
  model: deepseek-v4-pro-ga-260813
- name: ARK doubao-seed-2-0-code-preview-260215
  base_url: http://127.0.0.1:8897/v1
  api_key: local
  model: doubao-seed-2-0-code-preview-260215
- name: ARK doubao-seed-2-0-lite-260428
  base_url: http://127.0.0.1:8897/v1
  api_key: local
  model: doubao-seed-2-0-lite-260428
- name: ARK doubao-seed-2-0-mini-260428
  base_url: http://127.0.0.1:8897/v1
  api_key: local
  model: doubao-seed-2-0-mini-260428
- name: ARK doubao-seed-2-1-lite-260915
  base_url: http://127.0.0.1:8897/v1
  api_key: local
  model: doubao-seed-2-1-lite-260915
- name: ARK doubao-seed-2-1-pro-260628
  base_url: http://127.0.0.1:8897/v1
  api_key: local
  model: doubao-seed-2-1-pro-260628
- name: ARK doubao-seed-2-1-pro-260915
  base_url: http://127.0.0.1:8897/v1
  api_key: local
  model: doubao-seed-2-1-pro-260915
- name: ARK doubao-seed-2-1-turbo-260628
  base_url: http://127.0.0.1:8897/v1
  api_key: local
  model: doubao-seed-2-1-turbo-260628
- name: ARK doubao-seed-character-251128
  base_url: http://127.0.0.1:8897/v1
  api_key: local
  model: doubao-seed-character-251128
- name: ARK doubao-seed-character-260628
  base_url: http://127.0.0.1:8897/v1
  api_key: local
  model: doubao-seed-character-260628
- name: ARK glm-5-2-260617
  base_url: http://127.0.0.1:8897/v1
  api_key: local
  model: glm-5-2-260617
- name: ARK glm-5-3-flash-260828
  base_url: http://127.0.0.1:8897/v1
  api_key: local
  model: glm-5-3-flash-260828
```


### opencode — %USERPROFILE%\.config\opencode\opencode.jsonc

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "ocg": {
      "name": "OpenCode Go",
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://127.0.0.1:8899/v1",
        "apiKey": "local"
      },
      "models": {
        "deepseek-flash": {
          "name": "OCG deepseek-flash",
          "id": "deepseek-flash",
          "contextWindow": 1000000,
          "maxTokens": 384000
        },
        "deepseek-v4-flash": {
          "name": "OCG DeepSeek V4 Flash",
          "id": "deepseek-v4-flash",
          "contextWindow": 1000000,
          "maxTokens": 384000
        },
        "deepseek-v4-flash-vision-exp": {
          "name": "OCG DeepSeek V4 Flash Vision Exp",
          "id": "deepseek-v4-flash-vision-exp",
          "contextWindow": 1000000,
          "maxTokens": 384000
        },
        "deepseek-v4-pro": {
          "name": "OCG DeepSeek V4 Pro (New)",
          "id": "deepseek-v4-pro",
          "contextWindow": 1000000,
          "maxTokens": 384000
        },
        "deepseek-v4.1-flash": {
          "name": "OCG DeepSeek V4.1 Flash",
          "id": "deepseek-v4.1-flash",
          "contextWindow": 1000000,
          "maxTokens": 384000
        },
        "glm-5.1": {
          "name": "OCG glm-5.1",
          "id": "glm-5.1",
          "contextWindow": 200000,
          "maxTokens": 131072
        },
        "glm-5.2": {
          "name": "OCG GLM-5.2",
          "id": "glm-5.2",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "glm-5.3": {
          "name": "OCG GLM-5.3",
          "id": "glm-5.3",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "glm-5.3-flash": {
          "name": "OCG GLM-5.3-Flash",
          "id": "glm-5.3-flash",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "hy3": {
          "name": "OCG Hy3",
          "id": "hy3",
          "contextWindow": 256000,
          "maxTokens": 128000
        },
        "hy4-preview": {
          "name": "OCG Hy4 preview",
          "id": "hy4-preview",
          "contextWindow": 1024000,
          "maxTokens": 64000
        },
        "kimi-k2.6": {
          "name": "OCG Kimi K2.6",
          "id": "kimi-k2.6",
          "contextWindow": 262144,
          "maxTokens": 65536
        },
        "kimi-k2.7-code": {
          "name": "OCG Kimi K2.7 Code",
          "id": "kimi-k2.7-code",
          "contextWindow": 262144,
          "maxTokens": 262144
        },
        "kimi-k3": {
          "name": "OCG Kimi K3",
          "id": "kimi-k3",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        "longcat-2.0": {
          "name": "OCG LongCat-2.0",
          "id": "longcat-2.0",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "longcat-2.5-preview-free": {
          "name": "OCG LongCat 2.5 Preview Free",
          "id": "longcat-2.5-preview-free",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "mimo-v2.5": {
          "name": "OCG MiMo V2.5",
          "id": "mimo-v2.5",
          "contextWindow": 1000000,
          "maxTokens": 128000
        },
        "mimo-v2.5-pro": {
          "name": "OCG MiMo V2.5 Pro",
          "id": "mimo-v2.5-pro",
          "contextWindow": 1048576,
          "maxTokens": 128000
        },
        "mimo-v2.6-flash": {
          "name": "OCG MiMo-V2.6-Flash",
          "id": "mimo-v2.6-flash",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        "mimo-v2.6-pro": {
          "name": "OCG MiMo-V2.6-Pro",
          "id": "mimo-v2.6-pro",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        "minimax-m2.5": {
          "name": "OCG minimax-m2.5",
          "id": "minimax-m2.5",
          "contextWindow": 200000,
          "maxTokens": 131072
        },
        "minimax-m3": {
          "name": "OCG MiniMax-M3",
          "id": "minimax-m3",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "omen-alpha": {
          "name": "OCG omen-alpha",
          "id": "omen-alpha",
          "contextWindow": 262144,
          "maxTokens": 131072
        },
        "qwen3.6-plus": {
          "name": "OCG Qwen3.6 Plus",
          "id": "qwen3.6-plus",
          "contextWindow": 1000000,
          "maxTokens": 65536
        },
        "qwen3.7-max": {
          "name": "OCG Qwen3.7 Max",
          "id": "qwen3.7-max",
          "contextWindow": 1000000,
          "maxTokens": 65536
        },
        "qwen3.7-plus": {
          "name": "OCG Qwen3.7 Plus",
          "id": "qwen3.7-plus",
          "contextWindow": 1000000,
          "maxTokens": 65536
        },
        "qwen3.8-flash": {
          "name": "OCG Qwen3.8 Flash",
          "id": "qwen3.8-flash",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "qwen3.8-max": {
          "name": "OCG Qwen3.8 Max",
          "id": "qwen3.8-max",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "space-bunny": {
          "name": "OCG Space Bunny",
          "id": "space-bunny",
          "contextWindow": 1048576,
          "maxTokens": 524288
        },
        "step-5-preview-free": {
          "name": "OCG step-5-preview-free",
          "id": "step-5-preview-free",
          "contextWindow": 1000000,
          "maxTokens": 131072
        }
      }
    },
    "ccg": {
      "name": "Command Code GOAT",
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "https://api.commandcode.ai/provider/v1",
        "apiKey": "${COMMANDCODE_API_KEY}"
      },
      "models": {
        "MiniMaxAI/MiniMax-M2.5": {
          "name": "CCG MiniMax M2.5",
          "id": "MiniMaxAI/MiniMax-M2.5",
          "contextWindow": 200000,
          "maxTokens": 131072
        },
        "MiniMaxAI/MiniMax-M3": {
          "name": "CCG MiniMax M3",
          "id": "MiniMaxAI/MiniMax-M3",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "Qwen/Qwen3.6-Max-Preview": {
          "name": "CCG Qwen 3.6 Max Preview",
          "id": "Qwen/Qwen3.6-Max-Preview",
          "contextWindow": 200000,
          "maxTokens": 131072
        },
        "Qwen/Qwen3.6-Plus": {
          "name": "CCG Qwen 3.6 Plus",
          "id": "Qwen/Qwen3.6-Plus",
          "contextWindow": 200000,
          "maxTokens": 131072
        },
        "Qwen/Qwen3.7-Flash": {
          "name": "CCG Qwen 3.7 Flash",
          "id": "Qwen/Qwen3.7-Flash",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "Qwen/Qwen3.7-Max": {
          "name": "CCG Qwen 3.7 Max",
          "id": "Qwen/Qwen3.7-Max",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "Qwen/Qwen3.7-Plus": {
          "name": "CCG Qwen 3.7 Plus",
          "id": "Qwen/Qwen3.7-Plus",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "Qwen/Qwen3.8-27B": {
          "name": "CCG Qwen 3.8 27B",
          "id": "Qwen/Qwen3.8-27B",
          "contextWindow": 262144,
          "maxTokens": 131072
        },
        "Qwen/Qwen3.8-Flash": {
          "name": "CCG Qwen 3.8 Flash",
          "id": "Qwen/Qwen3.8-Flash",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "Qwen/Qwen3.8-Max": {
          "name": "CCG Qwen 3.8 Max",
          "id": "Qwen/Qwen3.8-Max",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "Qwen/Qwen3.8-Max-0902": {
          "name": "CCG Qwen 3.8 Max 0902",
          "id": "Qwen/Qwen3.8-Max-0902",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "Qwen/Qwen3.8-Omni-Flash": {
          "name": "CCG Qwen 3.8 Omni Flash",
          "id": "Qwen/Qwen3.8-Omni-Flash",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "deepseek/deepseek-v4-flash": {
          "name": "CCG DeepSeek V4 Flash (latest)",
          "id": "deepseek/deepseek-v4-flash",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "deepseek/deepseek-v4-flash-fast": {
          "name": "CCG DeepSeek V4 Flash Fast",
          "id": "deepseek/deepseek-v4-flash-fast",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "deepseek/deepseek-v4-flash-vision-exp": {
          "name": "CCG DeepSeek V4 Flash Vision (exp)",
          "id": "deepseek/deepseek-v4-flash-vision-exp",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "deepseek/deepseek-v4-pro": {
          "name": "CCG DeepSeek V4 Pro (latest)",
          "id": "deepseek/deepseek-v4-pro",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "deepseek/deepseek-v4.1-flash": {
          "name": "CCG DeepSeek V4.1 Flash",
          "id": "deepseek/deepseek-v4.1-flash",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "deepseek/deepseek-v4.1-flash-fast": {
          "name": "CCG DeepSeek V4.1 Flash Fast",
          "id": "deepseek/deepseek-v4.1-flash-fast",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "google/gemini-3.7-flash": {
          "name": "CCG Gemini 3.7 Flash",
          "id": "google/gemini-3.7-flash",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        "google/gemini-3.8-flash": {
          "name": "CCG Gemini 3.8 Flash",
          "id": "google/gemini-3.8-flash",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "gpt-5.6-luna": {
          "name": "CCG GPT-5.6 Luna",
          "id": "gpt-5.6-luna",
          "contextWindow": 1050000,
          "maxTokens": 131072
        },
        "gpt-5.6-sol": {
          "name": "CCG GPT-5.6 Sol",
          "id": "gpt-5.6-sol",
          "contextWindow": 1050000,
          "maxTokens": 131072
        },
        "gpt-6-luna": {
          "name": "CCG GPT-6 Luna",
          "id": "gpt-6-luna",
          "contextWindow": 1050000,
          "maxTokens": 131072
        },
        "inclusionai/ling-3.1-flash:free": {
          "name": "CCG Ling 3.1 Flash",
          "id": "inclusionai/ling-3.1-flash:free",
          "contextWindow": 262144,
          "maxTokens": 131072
        },
        "meituan/LongCat-2.0": {
          "name": "CCG LongCat 2.0",
          "id": "meituan/LongCat-2.0",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        "meta/muse-spark-1.2": {
          "name": "CCG Muse Spark 1.2",
          "id": "meta/muse-spark-1.2",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        "meta/muse-spark-1.2-contributor": {
          "name": "CCG Muse Spark 1.2 Contributor",
          "id": "meta/muse-spark-1.2-contributor",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        "meta/muse-spark-1.3": {
          "name": "CCG Muse Spark 1.3",
          "id": "meta/muse-spark-1.3",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        "meta/muse-spark-1.3-contributor": {
          "name": "CCG Muse Spark 1.3 Contributor",
          "id": "meta/muse-spark-1.3-contributor",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        "mistral/mistral-large-4": {
          "name": "CCG Mistral Large 4",
          "id": "mistral/mistral-large-4",
          "contextWindow": 524288,
          "maxTokens": 131072
        },
        "moonshotai/Kimi-K2.5": {
          "name": "CCG Kimi K2.5",
          "id": "moonshotai/Kimi-K2.5",
          "contextWindow": 256000,
          "maxTokens": 131072
        },
        "moonshotai/Kimi-K2.6": {
          "name": "CCG Kimi K2.6",
          "id": "moonshotai/Kimi-K2.6",
          "contextWindow": 256000,
          "maxTokens": 131072
        },
        "moonshotai/Kimi-K2.7-Code": {
          "name": "CCG Kimi K2.7 Code",
          "id": "moonshotai/Kimi-K2.7-Code",
          "contextWindow": 256000,
          "maxTokens": 131072
        },
        "moonshotai/Kimi-K2.7-Code-Highspeed": {
          "name": "CCG Kimi K2.7 Code HighSpeed",
          "id": "moonshotai/Kimi-K2.7-Code-Highspeed",
          "contextWindow": 262000,
          "maxTokens": 131072
        },
        "moonshotai/Kimi-K3": {
          "name": "CCG Kimi K3",
          "id": "moonshotai/Kimi-K3",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "nvidia/nemotron-3-ultra-550b-a55b": {
          "name": "CCG Nemotron 3 Ultra",
          "id": "nvidia/nemotron-3-ultra-550b-a55b",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "stealth/glyph-cluster:free": {
          "name": "CCG Glyph Cluster",
          "id": "stealth/glyph-cluster:free",
          "contextWindow": 256000,
          "maxTokens": 131072
        },
        "stepfun/Step-3.7-Flash": {
          "name": "CCG Step 3.7 Flash",
          "id": "stepfun/Step-3.7-Flash",
          "contextWindow": 256000,
          "maxTokens": 131072
        },
        "stepfun/Step-5-Preview": {
          "name": "CCG Step 5 Preview",
          "id": "stepfun/Step-5-Preview",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "tencent/hy3-paid": {
          "name": "CCG Tencent Hy3",
          "id": "tencent/hy3-paid",
          "contextWindow": 262144,
          "maxTokens": 131072
        },
        "tencent/hy4-preview": {
          "name": "CCG Tencent Hy4 Preview",
          "id": "tencent/hy4-preview",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        "xai/grok-4.5": {
          "name": "CCG Grok 4.5",
          "id": "xai/grok-4.5",
          "contextWindow": 500000,
          "maxTokens": 131072
        },
        "xai/grok-4.6": {
          "name": "CCG Grok 4.6",
          "id": "xai/grok-4.6",
          "contextWindow": 500000,
          "maxTokens": 131072
        },
        "xai/grok-4.7": {
          "name": "CCG Grok 4.7",
          "id": "xai/grok-4.7",
          "contextWindow": 500000,
          "maxTokens": 131072
        },
        "xiaomi/mimo-v2.5-pro": {
          "name": "CCG MiMo V2.5 Pro",
          "id": "xiaomi/mimo-v2.5-pro",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "xiaomi/mimo-v2.6-flash": {
          "name": "CCG MiMo V2.6 Flash",
          "id": "xiaomi/mimo-v2.6-flash",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        "xiaomi/mimo-v2.6-pro": {
          "name": "CCG MiMo V2.6 Pro",
          "id": "xiaomi/mimo-v2.6-pro",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        "xiaomi/mimo-v2.6-pro-ultraspeed": {
          "name": "CCG MiMo V2.6 Pro UltraSpeed",
          "id": "xiaomi/mimo-v2.6-pro-ultraspeed",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        "z-ai/glm-5.3-flash": {
          "name": "CCG GLM-5.3 Flash",
          "id": "z-ai/glm-5.3-flash",
          "contextWindow": 1048576,
          "maxTokens": 131072
        },
        "z-ai/glm-5.3-flashx": {
          "name": "CCG GLM-5.3 FlashX",
          "id": "z-ai/glm-5.3-flashx",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "zai-org/GLM-5": {
          "name": "CCG GLM-5",
          "id": "zai-org/GLM-5",
          "contextWindow": 200000,
          "maxTokens": 131072
        },
        "zai-org/GLM-5.2": {
          "name": "CCG GLM-5.2",
          "id": "zai-org/GLM-5.2",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "zai-org/GLM-5.2-Fast": {
          "name": "CCG GLM-5.2 Fast",
          "id": "zai-org/GLM-5.2-Fast",
          "contextWindow": 1000000,
          "maxTokens": 131072
        },
        "zai-org/GLM-5.3": {
          "name": "CCG GLM-5.3",
          "id": "zai-org/GLM-5.3",
          "contextWindow": 1000000,
          "maxTokens": 131072
        }
      }
    },
    "ds": {
      "name": "DeepSeek Official",
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://127.0.0.1:8896/v1",
        "apiKey": "local"
      },
      "models": {
        "deepseek-flash": {
          "name": "DS DeepSeek-V4.1-Flash",
          "id": "deepseek-flash",
          "contextWindow": 1048576,
          "maxTokens": 393216
        },
        "deepseek-v4-pro": {
          "name": "DS DeepSeek-V4-Pro",
          "id": "deepseek-v4-pro",
          "contextWindow": 1048576,
          "maxTokens": 393216
        }
      }
    },
    "ark": {
      "name": "Volcengine Ark",
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://127.0.0.1:8897/v1",
        "apiKey": "local"
      },
      "models": {
        "deepseek-v4-1-flash-260910": {
          "name": "ARK deepseek-v4-1-flash-260910",
          "id": "deepseek-v4-1-flash-260910",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        "deepseek-v4-flash-ga-260731": {
          "name": "ARK deepseek-v4-flash-ga-260731",
          "id": "deepseek-v4-flash-ga-260731",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        "deepseek-v4-pro-ga-260813": {
          "name": "ARK deepseek-v4-pro-ga-260813",
          "id": "deepseek-v4-pro-ga-260813",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        "doubao-seed-2-0-code-preview-260215": {
          "name": "ARK doubao-seed-2-0-code-preview-260215",
          "id": "doubao-seed-2-0-code-preview-260215",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        "doubao-seed-2-0-lite-260428": {
          "name": "ARK doubao-seed-2-0-lite-260428",
          "id": "doubao-seed-2-0-lite-260428",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        "doubao-seed-2-0-mini-260428": {
          "name": "ARK doubao-seed-2-0-mini-260428",
          "id": "doubao-seed-2-0-mini-260428",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        "doubao-seed-2-1-lite-260915": {
          "name": "ARK doubao-seed-2-1-lite-260915",
          "id": "doubao-seed-2-1-lite-260915",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        "doubao-seed-2-1-pro-260628": {
          "name": "ARK doubao-seed-2-1-pro-260628",
          "id": "doubao-seed-2-1-pro-260628",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        "doubao-seed-2-1-pro-260915": {
          "name": "ARK doubao-seed-2-1-pro-260915",
          "id": "doubao-seed-2-1-pro-260915",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        "doubao-seed-2-1-turbo-260628": {
          "name": "ARK doubao-seed-2-1-turbo-260628",
          "id": "doubao-seed-2-1-turbo-260628",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        "doubao-seed-character-251128": {
          "name": "ARK doubao-seed-character-251128",
          "id": "doubao-seed-character-251128",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        "doubao-seed-character-260628": {
          "name": "ARK doubao-seed-character-260628",
          "id": "doubao-seed-character-260628",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        "glm-5-2-260617": {
          "name": "ARK glm-5-2-260617",
          "id": "glm-5-2-260617",
          "contextWindow": 262144,
          "maxTokens": 32768
        },
        "glm-5-3-flash-260828": {
          "name": "ARK glm-5-3-flash-260828",
          "id": "glm-5-3-flash-260828",
          "contextWindow": 262144,
          "maxTokens": 32768
        }
      }
    }
  },
  "model": "ocg/longcat-2.5-preview-free",
  "disabled_providers": [
    "opencode-go"
  ]
}
```


### code_buddy — %USERPROFILE%\.codebuddy\models.json

```json
{
  "models": [
    {
      "id": "ocg/deepseek-flash",
      "name": "OCG deepseek-flash",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 384000,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/deepseek-v4-flash",
      "name": "OCG DeepSeek V4 Flash",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 384000,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/deepseek-v4-flash-vision-exp",
      "name": "OCG DeepSeek V4 Flash Vision Exp",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 384000,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/deepseek-v4-pro",
      "name": "OCG DeepSeek V4 Pro (New)",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 384000,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/deepseek-v4.1-flash",
      "name": "OCG DeepSeek V4.1 Flash",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 384000,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/glm-5.1",
      "name": "OCG glm-5.1",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 200000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/glm-5.2",
      "name": "OCG GLM-5.2",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/glm-5.3",
      "name": "OCG GLM-5.3",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/glm-5.3-flash",
      "name": "OCG GLM-5.3-Flash",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/hy3",
      "name": "OCG Hy3",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 256000,
      "maxOutputTokens": 128000,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/hy4-preview",
      "name": "OCG Hy4 preview",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1024000,
      "maxOutputTokens": 64000,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/kimi-k2.6",
      "name": "OCG Kimi K2.6",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262144,
      "maxOutputTokens": 65536,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/kimi-k2.7-code",
      "name": "OCG Kimi K2.7 Code",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262144,
      "maxOutputTokens": 262144,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/kimi-k3",
      "name": "OCG Kimi K3",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1048576,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/longcat-2.0",
      "name": "OCG LongCat-2.0",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/longcat-2.5-preview-free",
      "name": "OCG LongCat 2.5 Preview Free",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/mimo-v2.5",
      "name": "OCG MiMo V2.5",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 128000,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/mimo-v2.5-pro",
      "name": "OCG MiMo V2.5 Pro",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1048576,
      "maxOutputTokens": 128000,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/mimo-v2.6-flash",
      "name": "OCG MiMo-V2.6-Flash",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1048576,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/mimo-v2.6-pro",
      "name": "OCG MiMo-V2.6-Pro",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1048576,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/minimax-m2.5",
      "name": "OCG minimax-m2.5",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 200000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/minimax-m3",
      "name": "OCG MiniMax-M3",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/omen-alpha",
      "name": "OCG omen-alpha",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262144,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/qwen3.6-plus",
      "name": "OCG Qwen3.6 Plus",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 65536,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/qwen3.7-max",
      "name": "OCG Qwen3.7 Max",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 65536,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/qwen3.7-plus",
      "name": "OCG Qwen3.7 Plus",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 65536,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/qwen3.8-flash",
      "name": "OCG Qwen3.8 Flash",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/qwen3.8-max",
      "name": "OCG Qwen3.8 Max",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/space-bunny",
      "name": "OCG Space Bunny",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1048576,
      "maxOutputTokens": 524288,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ocg/step-5-preview-free",
      "name": "OCG step-5-preview-free",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/MiniMaxAI/MiniMax-M2.5",
      "name": "CCG MiniMax M2.5",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 200000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/MiniMaxAI/MiniMax-M3",
      "name": "CCG MiniMax M3",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/Qwen/Qwen3.6-Max-Preview",
      "name": "CCG Qwen 3.6 Max Preview",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 200000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/Qwen/Qwen3.6-Plus",
      "name": "CCG Qwen 3.6 Plus",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 200000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/Qwen/Qwen3.7-Flash",
      "name": "CCG Qwen 3.7 Flash",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/Qwen/Qwen3.7-Max",
      "name": "CCG Qwen 3.7 Max",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/Qwen/Qwen3.7-Plus",
      "name": "CCG Qwen 3.7 Plus",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/Qwen/Qwen3.8-27B",
      "name": "CCG Qwen 3.8 27B",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262144,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/Qwen/Qwen3.8-Flash",
      "name": "CCG Qwen 3.8 Flash",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/Qwen/Qwen3.8-Max",
      "name": "CCG Qwen 3.8 Max",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/Qwen/Qwen3.8-Max-0902",
      "name": "CCG Qwen 3.8 Max 0902",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/Qwen/Qwen3.8-Omni-Flash",
      "name": "CCG Qwen 3.8 Omni Flash",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/deepseek/deepseek-v4-flash",
      "name": "CCG DeepSeek V4 Flash (latest)",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/deepseek/deepseek-v4-flash-fast",
      "name": "CCG DeepSeek V4 Flash Fast",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/deepseek/deepseek-v4-flash-vision-exp",
      "name": "CCG DeepSeek V4 Flash Vision (exp)",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/deepseek/deepseek-v4-pro",
      "name": "CCG DeepSeek V4 Pro (latest)",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/deepseek/deepseek-v4.1-flash",
      "name": "CCG DeepSeek V4.1 Flash",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/deepseek/deepseek-v4.1-flash-fast",
      "name": "CCG DeepSeek V4.1 Flash Fast",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/google/gemini-3.7-flash",
      "name": "CCG Gemini 3.7 Flash",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1048576,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/google/gemini-3.8-flash",
      "name": "CCG Gemini 3.8 Flash",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/gpt-5.6-luna",
      "name": "CCG GPT-5.6 Luna",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1050000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/gpt-5.6-sol",
      "name": "CCG GPT-5.6 Sol",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1050000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/gpt-6-luna",
      "name": "CCG GPT-6 Luna",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1050000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/inclusionai/ling-3.1-flash:free",
      "name": "CCG Ling 3.1 Flash",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262144,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/meituan/LongCat-2.0",
      "name": "CCG LongCat 2.0",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1048576,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/meta/muse-spark-1.2",
      "name": "CCG Muse Spark 1.2",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1048576,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/meta/muse-spark-1.2-contributor",
      "name": "CCG Muse Spark 1.2 Contributor",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1048576,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/meta/muse-spark-1.3",
      "name": "CCG Muse Spark 1.3",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1048576,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/meta/muse-spark-1.3-contributor",
      "name": "CCG Muse Spark 1.3 Contributor",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1048576,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/mistral/mistral-large-4",
      "name": "CCG Mistral Large 4",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 524288,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/moonshotai/Kimi-K2.5",
      "name": "CCG Kimi K2.5",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 256000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/moonshotai/Kimi-K2.6",
      "name": "CCG Kimi K2.6",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 256000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/moonshotai/Kimi-K2.7-Code",
      "name": "CCG Kimi K2.7 Code",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 256000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/moonshotai/Kimi-K2.7-Code-Highspeed",
      "name": "CCG Kimi K2.7 Code HighSpeed",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/moonshotai/Kimi-K3",
      "name": "CCG Kimi K3",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/nvidia/nemotron-3-ultra-550b-a55b",
      "name": "CCG Nemotron 3 Ultra",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/stealth/glyph-cluster:free",
      "name": "CCG Glyph Cluster",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 256000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/stepfun/Step-3.7-Flash",
      "name": "CCG Step 3.7 Flash",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 256000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/stepfun/Step-5-Preview",
      "name": "CCG Step 5 Preview",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/tencent/hy3-paid",
      "name": "CCG Tencent Hy3",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262144,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/tencent/hy4-preview",
      "name": "CCG Tencent Hy4 Preview",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1048576,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/xai/grok-4.5",
      "name": "CCG Grok 4.5",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 500000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/xai/grok-4.6",
      "name": "CCG Grok 4.6",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 500000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/xai/grok-4.7",
      "name": "CCG Grok 4.7",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 500000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/xiaomi/mimo-v2.5-pro",
      "name": "CCG MiMo V2.5 Pro",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/xiaomi/mimo-v2.6-flash",
      "name": "CCG MiMo V2.6 Flash",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1048576,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/xiaomi/mimo-v2.6-pro",
      "name": "CCG MiMo V2.6 Pro",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1048576,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/xiaomi/mimo-v2.6-pro-ultraspeed",
      "name": "CCG MiMo V2.6 Pro UltraSpeed",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1048576,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/z-ai/glm-5.3-flash",
      "name": "CCG GLM-5.3 Flash",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1048576,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/z-ai/glm-5.3-flashx",
      "name": "CCG GLM-5.3 FlashX",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/zai-org/GLM-5",
      "name": "CCG GLM-5",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 200000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/zai-org/GLM-5.2",
      "name": "CCG GLM-5.2",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/zai-org/GLM-5.2-Fast",
      "name": "CCG GLM-5.2 Fast",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ccg/zai-org/GLM-5.3",
      "name": "CCG GLM-5.3",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1000000,
      "maxOutputTokens": 131072,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ds/deepseek-flash",
      "name": "DS deepseek-flash",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1048576,
      "maxOutputTokens": 393216,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ds/deepseek-v4-pro",
      "name": "DS deepseek-v4-pro",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 1048576,
      "maxOutputTokens": 393216,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ark/deepseek-v4-1-flash-260910",
      "name": "ARK deepseek-v4-1-flash-260910",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262144,
      "maxOutputTokens": 32768,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ark/deepseek-v4-flash-ga-260731",
      "name": "ARK deepseek-v4-flash-ga-260731",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262144,
      "maxOutputTokens": 32768,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ark/deepseek-v4-pro-ga-260813",
      "name": "ARK deepseek-v4-pro-ga-260813",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262144,
      "maxOutputTokens": 32768,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ark/doubao-seed-2-0-code-preview-260215",
      "name": "ARK doubao-seed-2-0-code-preview-260215",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262144,
      "maxOutputTokens": 32768,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ark/doubao-seed-2-0-lite-260428",
      "name": "ARK doubao-seed-2-0-lite-260428",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262144,
      "maxOutputTokens": 32768,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ark/doubao-seed-2-0-mini-260428",
      "name": "ARK doubao-seed-2-0-mini-260428",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262144,
      "maxOutputTokens": 32768,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ark/doubao-seed-2-1-lite-260915",
      "name": "ARK doubao-seed-2-1-lite-260915",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262144,
      "maxOutputTokens": 32768,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ark/doubao-seed-2-1-pro-260628",
      "name": "ARK doubao-seed-2-1-pro-260628",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262144,
      "maxOutputTokens": 32768,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ark/doubao-seed-2-1-pro-260915",
      "name": "ARK doubao-seed-2-1-pro-260915",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262144,
      "maxOutputTokens": 32768,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ark/doubao-seed-2-1-turbo-260628",
      "name": "ARK doubao-seed-2-1-turbo-260628",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262144,
      "maxOutputTokens": 32768,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ark/doubao-seed-character-251128",
      "name": "ARK doubao-seed-character-251128",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262144,
      "maxOutputTokens": 32768,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ark/doubao-seed-character-260628",
      "name": "ARK doubao-seed-character-260628",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262144,
      "maxOutputTokens": 32768,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ark/glm-5-2-260617",
      "name": "ARK glm-5-2-260617",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262144,
      "maxOutputTokens": 32768,
      "supportsReasoning": true,
      "supportsImages": true
    },
    {
      "id": "ark/glm-5-3-flash-260828",
      "name": "ARK glm-5-3-flash-260828",
      "url": "http://127.0.0.1:4000/v1",
      "apiKey": "local",
      "maxInputTokens": 262144,
      "maxOutputTokens": 32768,
      "supportsReasoning": true,
      "supportsImages": true
    }
  ],
  "availableModels": [
    "ocg/deepseek-flash",
    "ocg/deepseek-v4-flash",
    "ocg/deepseek-v4-flash-vision-exp",
    "ocg/deepseek-v4-pro",
    "ocg/deepseek-v4.1-flash",
    "ocg/glm-5.1",
    "ocg/glm-5.2",
    "ocg/glm-5.3",
    "ocg/glm-5.3-flash",
    "ocg/hy3",
    "ocg/hy4-preview",
    "ocg/kimi-k2.6",
    "ocg/kimi-k2.7-code",
    "ocg/kimi-k3",
    "ocg/longcat-2.0",
    "ocg/longcat-2.5-preview-free",
    "ocg/mimo-v2.5",
    "ocg/mimo-v2.5-pro",
    "ocg/mimo-v2.6-flash",
    "ocg/mimo-v2.6-pro",
    "ocg/minimax-m2.5",
    "ocg/minimax-m3",
    "ocg/omen-alpha",
    "ocg/qwen3.6-plus",
    "ocg/qwen3.7-max",
    "ocg/qwen3.7-plus",
    "ocg/qwen3.8-flash",
    "ocg/qwen3.8-max",
    "ocg/space-bunny",
    "ocg/step-5-preview-free",
    "ccg/MiniMaxAI/MiniMax-M2.5",
    "ccg/MiniMaxAI/MiniMax-M3",
    "ccg/Qwen/Qwen3.6-Max-Preview",
    "ccg/Qwen/Qwen3.6-Plus",
    "ccg/Qwen/Qwen3.7-Flash",
    "ccg/Qwen/Qwen3.7-Max",
    "ccg/Qwen/Qwen3.7-Plus",
    "ccg/Qwen/Qwen3.8-27B",
    "ccg/Qwen/Qwen3.8-Flash",
    "ccg/Qwen/Qwen3.8-Max",
    "ccg/Qwen/Qwen3.8-Max-0902",
    "ccg/Qwen/Qwen3.8-Omni-Flash",
    "ccg/deepseek/deepseek-v4-flash",
    "ccg/deepseek/deepseek-v4-flash-fast",
    "ccg/deepseek/deepseek-v4-flash-vision-exp",
    "ccg/deepseek/deepseek-v4-pro",
    "ccg/deepseek/deepseek-v4.1-flash",
    "ccg/deepseek/deepseek-v4.1-flash-fast",
    "ccg/google/gemini-3.7-flash",
    "ccg/google/gemini-3.8-flash",
    "ccg/gpt-5.6-luna",
    "ccg/gpt-5.6-sol",
    "ccg/gpt-6-luna",
    "ccg/inclusionai/ling-3.1-flash:free",
    "ccg/meituan/LongCat-2.0",
    "ccg/meta/muse-spark-1.2",
    "ccg/meta/muse-spark-1.2-contributor",
    "ccg/meta/muse-spark-1.3",
    "ccg/meta/muse-spark-1.3-contributor",
    "ccg/mistral/mistral-large-4",
    "ccg/moonshotai/Kimi-K2.5",
    "ccg/moonshotai/Kimi-K2.6",
    "ccg/moonshotai/Kimi-K2.7-Code",
    "ccg/moonshotai/Kimi-K2.7-Code-Highspeed",
    "ccg/moonshotai/Kimi-K3",
    "ccg/nvidia/nemotron-3-ultra-550b-a55b",
    "ccg/stealth/glyph-cluster:free",
    "ccg/stepfun/Step-3.7-Flash",
    "ccg/stepfun/Step-5-Preview",
    "ccg/tencent/hy3-paid",
    "ccg/tencent/hy4-preview",
    "ccg/xai/grok-4.5",
    "ccg/xai/grok-4.6",
    "ccg/xai/grok-4.7",
    "ccg/xiaomi/mimo-v2.5-pro",
    "ccg/xiaomi/mimo-v2.6-flash",
    "ccg/xiaomi/mimo-v2.6-pro",
    "ccg/xiaomi/mimo-v2.6-pro-ultraspeed",
    "ccg/z-ai/glm-5.3-flash",
    "ccg/z-ai/glm-5.3-flashx",
    "ccg/zai-org/GLM-5",
    "ccg/zai-org/GLM-5.2",
    "ccg/zai-org/GLM-5.2-Fast",
    "ccg/zai-org/GLM-5.3",
    "ds/deepseek-flash",
    "ds/deepseek-v4-pro",
    "ark/deepseek-v4-1-flash-260910",
    "ark/deepseek-v4-flash-ga-260731",
    "ark/deepseek-v4-pro-ga-260813",
    "ark/doubao-seed-2-0-code-preview-260215",
    "ark/doubao-seed-2-0-lite-260428",
    "ark/doubao-seed-2-0-mini-260428",
    "ark/doubao-seed-2-1-lite-260915",
    "ark/doubao-seed-2-1-pro-260628",
    "ark/doubao-seed-2-1-pro-260915",
    "ark/doubao-seed-2-1-turbo-260628",
    "ark/doubao-seed-character-251128",
    "ark/doubao-seed-character-260628",
    "ark/glm-5-2-260617",
    "ark/glm-5-3-flash-260828"
  ]
}
```


### dsh — %USERPROFILE%\.dsh\settings.yaml

```yaml
# DeepSeek Harness 的模型路由（由 codeg 配置项目生成）
#
llm-pi-ai:
  providers:
    ocg:
      displayName: OpenCode Go
      api: openai-completions
      baseURL: http://127.0.0.1:4000/v1
      apiKeyEnv: DEEPSEEK_API_KEY
      models:
        - id: ocg/deepseek-flash
          name: OCG deepseek-flash
          contextWindow: 1000000
        - id: ocg/deepseek-v4-flash
          name: OCG deepseek-v4-flash
          contextWindow: 1000000
        - id: ocg/deepseek-v4-flash-vision-exp
          name: OCG deepseek-v4-flash-vision-exp
          contextWindow: 1000000
        - id: ocg/deepseek-v4-pro
          name: OCG deepseek-v4-pro
          contextWindow: 1000000
        - id: ocg/deepseek-v4.1-flash
          name: OCG deepseek-v4.1-flash
          contextWindow: 1000000
        - id: ocg/glm-5.1
          name: OCG glm-5.1
          contextWindow: 200000
        - id: ocg/glm-5.2
          name: OCG glm-5.2
          contextWindow: 1000000
        - id: ocg/glm-5.3
          name: OCG glm-5.3
          contextWindow: 1000000
        - id: ocg/glm-5.3-flash
          name: OCG glm-5.3-flash
          contextWindow: 1000000
        - id: ocg/hy3
          name: OCG hy3
          contextWindow: 256000
        - id: ocg/hy4-preview
          name: OCG hy4-preview
          contextWindow: 1024000
        - id: ocg/kimi-k2.6
          name: OCG kimi-k2.6
          contextWindow: 262144
        - id: ocg/kimi-k2.7-code
          name: OCG kimi-k2.7-code
          contextWindow: 262144
        - id: ocg/kimi-k3
          name: OCG kimi-k3
          contextWindow: 1048576
        - id: ocg/longcat-2.0
          name: OCG longcat-2.0
          contextWindow: 1000000
        - id: ocg/longcat-2.5-preview-free
          name: OCG longcat-2.5-preview-free
          contextWindow: 1000000
        - id: ocg/mimo-v2.5
          name: OCG mimo-v2.5
          contextWindow: 1000000
        - id: ocg/mimo-v2.5-pro
          name: OCG mimo-v2.5-pro
          contextWindow: 1048576
        - id: ocg/mimo-v2.6-flash
          name: OCG mimo-v2.6-flash
          contextWindow: 1048576
        - id: ocg/mimo-v2.6-pro
          name: OCG mimo-v2.6-pro
          contextWindow: 1048576
        - id: ocg/minimax-m2.5
          name: OCG minimax-m2.5
          contextWindow: 200000
        - id: ocg/minimax-m3
          name: OCG minimax-m3
          contextWindow: 1000000
        - id: ocg/omen-alpha
          name: OCG omen-alpha
          contextWindow: 262144
        - id: ocg/qwen3.6-plus
          name: OCG qwen3.6-plus
          contextWindow: 1000000
        - id: ocg/qwen3.7-max
          name: OCG qwen3.7-max
          contextWindow: 1000000
        - id: ocg/qwen3.7-plus
          name: OCG qwen3.7-plus
          contextWindow: 1000000
        - id: ocg/qwen3.8-flash
          name: OCG qwen3.8-flash
          contextWindow: 1000000
        - id: ocg/qwen3.8-max
          name: OCG qwen3.8-max
          contextWindow: 1000000
        - id: ocg/space-bunny
          name: OCG space-bunny
          contextWindow: 1048576
        - id: ocg/step-5-preview-free
          name: OCG step-5-preview-free
          contextWindow: 1000000
    ccg:
      displayName: Command Code GOAT
      api: openai-completions
      baseURL: http://127.0.0.1:4000/v1
      apiKeyEnv: DEEPSEEK_API_KEY
      models:
        - id: ccg/MiniMaxAI/MiniMax-M2.5
          name: CCG MiniMaxAI/MiniMax-M2.5
          contextWindow: 200000
        - id: ccg/MiniMaxAI/MiniMax-M3
          name: CCG MiniMaxAI/MiniMax-M3
          contextWindow: 1000000
        - id: ccg/Qwen/Qwen3.6-Max-Preview
          name: CCG Qwen/Qwen3.6-Max-Preview
          contextWindow: 200000
        - id: ccg/Qwen/Qwen3.6-Plus
          name: CCG Qwen/Qwen3.6-Plus
          contextWindow: 200000
        - id: ccg/Qwen/Qwen3.7-Flash
          name: CCG Qwen/Qwen3.7-Flash
          contextWindow: 1000000
        - id: ccg/Qwen/Qwen3.7-Max
          name: CCG Qwen/Qwen3.7-Max
          contextWindow: 1000000
        - id: ccg/Qwen/Qwen3.7-Plus
          name: CCG Qwen/Qwen3.7-Plus
          contextWindow: 1000000
        - id: ccg/Qwen/Qwen3.8-27B
          name: CCG Qwen/Qwen3.8-27B
          contextWindow: 262144
        - id: ccg/Qwen/Qwen3.8-Flash
          name: CCG Qwen/Qwen3.8-Flash
          contextWindow: 1000000
        - id: ccg/Qwen/Qwen3.8-Max
          name: CCG Qwen/Qwen3.8-Max
          contextWindow: 1000000
        - id: ccg/Qwen/Qwen3.8-Max-0902
          name: CCG Qwen/Qwen3.8-Max-0902
          contextWindow: 1000000
        - id: ccg/Qwen/Qwen3.8-Omni-Flash
          name: CCG Qwen/Qwen3.8-Omni-Flash
          contextWindow: 1000000
        - id: ccg/deepseek/deepseek-v4-flash
          name: CCG deepseek/deepseek-v4-flash
          contextWindow: 1000000
        - id: ccg/deepseek/deepseek-v4-flash-fast
          name: CCG deepseek/deepseek-v4-flash-fast
          contextWindow: 1000000
        - id: ccg/deepseek/deepseek-v4-flash-vision-exp
          name: CCG deepseek/deepseek-v4-flash-vision-exp
          contextWindow: 1000000
        - id: ccg/deepseek/deepseek-v4-pro
          name: CCG deepseek/deepseek-v4-pro
          contextWindow: 1000000
        - id: ccg/deepseek/deepseek-v4.1-flash
          name: CCG deepseek/deepseek-v4.1-flash
          contextWindow: 1000000
        - id: ccg/deepseek/deepseek-v4.1-flash-fast
          name: CCG deepseek/deepseek-v4.1-flash-fast
          contextWindow: 1000000
        - id: ccg/google/gemini-3.7-flash
          name: CCG google/gemini-3.7-flash
          contextWindow: 1048576
        - id: ccg/google/gemini-3.8-flash
          name: CCG google/gemini-3.8-flash
          contextWindow: 1000000
        - id: ccg/gpt-5.6-luna
          name: CCG gpt-5.6-luna
          contextWindow: 1050000
        - id: ccg/gpt-5.6-sol
          name: CCG gpt-5.6-sol
          contextWindow: 1050000
        - id: ccg/gpt-6-luna
          name: CCG gpt-6-luna
          contextWindow: 1050000
        - id: ccg/inclusionai/ling-3.1-flash:free
          name: CCG inclusionai/ling-3.1-flash:free
          contextWindow: 262144
        - id: ccg/meituan/LongCat-2.0
          name: CCG meituan/LongCat-2.0
          contextWindow: 1048576
        - id: ccg/meta/muse-spark-1.2
          name: CCG meta/muse-spark-1.2
          contextWindow: 1048576
        - id: ccg/meta/muse-spark-1.2-contributor
          name: CCG meta/muse-spark-1.2-contributor
          contextWindow: 1048576
        - id: ccg/meta/muse-spark-1.3
          name: CCG meta/muse-spark-1.3
          contextWindow: 1048576
        - id: ccg/meta/muse-spark-1.3-contributor
          name: CCG meta/muse-spark-1.3-contributor
          contextWindow: 1048576
        - id: ccg/mistral/mistral-large-4
          name: CCG mistral/mistral-large-4
          contextWindow: 524288
        - id: ccg/moonshotai/Kimi-K2.5
          name: CCG moonshotai/Kimi-K2.5
          contextWindow: 256000
        - id: ccg/moonshotai/Kimi-K2.6
          name: CCG moonshotai/Kimi-K2.6
          contextWindow: 256000
        - id: ccg/moonshotai/Kimi-K2.7-Code
          name: CCG moonshotai/Kimi-K2.7-Code
          contextWindow: 256000
        - id: ccg/moonshotai/Kimi-K2.7-Code-Highspeed
          name: CCG moonshotai/Kimi-K2.7-Code-Highspeed
          contextWindow: 262000
        - id: ccg/moonshotai/Kimi-K3
          name: CCG moonshotai/Kimi-K3
          contextWindow: 1000000
        - id: ccg/nvidia/nemotron-3-ultra-550b-a55b
          name: CCG nvidia/nemotron-3-ultra-550b-a55b
          contextWindow: 1000000
        - id: ccg/stealth/glyph-cluster:free
          name: CCG stealth/glyph-cluster:free
          contextWindow: 256000
        - id: ccg/stepfun/Step-3.7-Flash
          name: CCG stepfun/Step-3.7-Flash
          contextWindow: 256000
        - id: ccg/stepfun/Step-5-Preview
          name: CCG stepfun/Step-5-Preview
          contextWindow: 1000000
        - id: ccg/tencent/hy3-paid
          name: CCG tencent/hy3-paid
          contextWindow: 262144
        - id: ccg/tencent/hy4-preview
          name: CCG tencent/hy4-preview
          contextWindow: 1048576
        - id: ccg/xai/grok-4.5
          name: CCG xai/grok-4.5
          contextWindow: 500000
        - id: ccg/xai/grok-4.6
          name: CCG xai/grok-4.6
          contextWindow: 500000
        - id: ccg/xai/grok-4.7
          name: CCG xai/grok-4.7
          contextWindow: 500000
        - id: ccg/xiaomi/mimo-v2.5-pro
          name: CCG xiaomi/mimo-v2.5-pro
          contextWindow: 1000000
        - id: ccg/xiaomi/mimo-v2.6-flash
          name: CCG xiaomi/mimo-v2.6-flash
          contextWindow: 1048576
        - id: ccg/xiaomi/mimo-v2.6-pro
          name: CCG xiaomi/mimo-v2.6-pro
          contextWindow: 1048576
        - id: ccg/xiaomi/mimo-v2.6-pro-ultraspeed
          name: CCG xiaomi/mimo-v2.6-pro-ultraspeed
          contextWindow: 1048576
        - id: ccg/z-ai/glm-5.3-flash
          name: CCG z-ai/glm-5.3-flash
          contextWindow: 1048576
        - id: ccg/z-ai/glm-5.3-flashx
          name: CCG z-ai/glm-5.3-flashx
          contextWindow: 1000000
        - id: ccg/zai-org/GLM-5
          name: CCG zai-org/GLM-5
          contextWindow: 200000
        - id: ccg/zai-org/GLM-5.2
          name: CCG zai-org/GLM-5.2
          contextWindow: 1000000
        - id: ccg/zai-org/GLM-5.2-Fast
          name: CCG zai-org/GLM-5.2-Fast
          contextWindow: 1000000
        - id: ccg/zai-org/GLM-5.3
          name: CCG zai-org/GLM-5.3
          contextWindow: 1000000
    ds:
      displayName: DeepSeek Official
      api: openai-completions
      baseURL: http://127.0.0.1:4000/v1
      apiKeyEnv: DEEPSEEK_API_KEY
      models:
        - id: ds/deepseek-flash
          name: DS deepseek-flash
          contextWindow: 1048576
        - id: ds/deepseek-v4-pro
          name: DS deepseek-v4-pro
          contextWindow: 1048576
    ark:
      displayName: Volcengine Ark
      api: openai-completions
      baseURL: http://127.0.0.1:4000/v1
      apiKeyEnv: DEEPSEEK_API_KEY
      models:
        - id: ark/deepseek-v4-1-flash-260910
          name: ARK deepseek-v4-1-flash-260910
          contextWindow: 262144
        - id: ark/deepseek-v4-flash-ga-260731
          name: ARK deepseek-v4-flash-ga-260731
          contextWindow: 262144
        - id: ark/deepseek-v4-pro-ga-260813
          name: ARK deepseek-v4-pro-ga-260813
          contextWindow: 262144
        - id: ark/doubao-seed-2-0-code-preview-260215
          name: ARK doubao-seed-2-0-code-preview-260215
          contextWindow: 262144
        - id: ark/doubao-seed-2-0-lite-260428
          name: ARK doubao-seed-2-0-lite-260428
          contextWindow: 262144
        - id: ark/doubao-seed-2-0-mini-260428
          name: ARK doubao-seed-2-0-mini-260428
          contextWindow: 262144
        - id: ark/doubao-seed-2-1-lite-260915
          name: ARK doubao-seed-2-1-lite-260915
          contextWindow: 262144
        - id: ark/doubao-seed-2-1-pro-260628
          name: ARK doubao-seed-2-1-pro-260628
          contextWindow: 262144
        - id: ark/doubao-seed-2-1-pro-260915
          name: ARK doubao-seed-2-1-pro-260915
          contextWindow: 262144
        - id: ark/doubao-seed-2-1-turbo-260628
          name: ARK doubao-seed-2-1-turbo-260628
          contextWindow: 262144
        - id: ark/doubao-seed-character-251128
          name: ARK doubao-seed-character-251128
          contextWindow: 262144
        - id: ark/doubao-seed-character-260628
          name: ARK doubao-seed-character-260628
          contextWindow: 262144
        - id: ark/glm-5-2-260617
          name: ARK glm-5-2-260617
          contextWindow: 262144
        - id: ark/glm-5-3-flash-260828
          name: ARK glm-5-3-flash-260828
          contextWindow: 262144
```


### open_claw — %USERPROFILE%\.openclaw\openclaw.json（节选）

```json
{
  "models": {
    "providers": {
      "ocg": {
        "baseUrl": "http://127.0.0.1:8899/v1",
        "apiKey": "local",
        "api": "openai-completions",
        "models_count": 30,
        "_models_sample": [
          "deepseek-flash",
          "deepseek-v4-flash",
          "deepseek-v4-flash-vision-exp"
        ]
      },
      "ccg": {
        "baseUrl": "https://api.commandcode.ai/provider/v1",
        "apiKey": "local",
        "api": "openai-completions",
        "models_count": 54,
        "_models_sample": [
          "MiniMaxAI/MiniMax-M2.5",
          "MiniMaxAI/MiniMax-M3",
          "Qwen/Qwen3.6-Max-Preview"
        ]
      },
      "ds": {
        "baseUrl": "http://127.0.0.1:8896/v1",
        "apiKey": "local",
        "api": "openai-completions",
        "models_count": 2,
        "_models_sample": [
          "deepseek-flash",
          "deepseek-v4-pro"
        ]
      },
      "ark": {
        "baseUrl": "http://127.0.0.1:8897/v1",
        "apiKey": "local",
        "api": "openai-completions",
        "models_count": 14,
        "_models_sample": [
          "deepseek-v4-1-flash-260910",
          "deepseek-v4-flash-ga-260731",
          "deepseek-v4-pro-ga-260813"
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": null,
      "modelPolicy": {
        "allow_count": 0,
        "_sample": []
      },
      "models_count": 100
    },
    "entries": {
      "main": {}
    }
  }
}
```


### cline — %USERPROFILE%\.cline\data\settings\providers.json

```json
{
  "version": 1,
  "lastUsedProvider": "openai-compatible",
  "modes": {},
  "providers": {
    "openai-compatible": {
      "settings": {
        "provider": "openai-compatible",
        "apiKey": "local",
        "model": "ocg/longcat-2.5-preview-free",
        "baseUrl": "http://127.0.0.1:4000/v1"
      },
      "updatedAt": "2026-10-10T05:44:03.000Z",
      "tokenSource": "manual"
    }
  }
}
```


### cline — %USERPROFILE%\.cline\data\settings\models.json（结构示例）

```json
{
  "version": 1,
  "providers": {
    "openai-compatible": {
      "provider": {
        "name": "LiteLLM (OpenAI Compatible)",
        "baseUrl": "http://127.0.0.1:4000/v1",
        "defaultModelId": "ocg/longcat-2.5-preview-free",
        "capabilities": [
          "tools",
          "streaming"
        ]
      },
      "models": {
        "ocg/deepseek-flash": {
          "id": "ocg/deepseek-flash",
          "name": "OCG deepseek-flash",
          "contextWindow": 1000000,
          "maxTokens": 384000,
          "supportsReasoning": true,
          "supportsVision": true,
          "supportsAttachments": true,
          "capabilities": [
            "tools",
            "streaming"
          ]
        },
        "ocg/deepseek-v4-flash": {
          "id": "ocg/deepseek-v4-flash",
          "name": "OCG DeepSeek V4 Flash",
          "contextWindow": 1000000,
          "maxTokens": 384000,
          "supportsReasoning": true,
          "supportsVision": true,
          "supportsAttachments": true,
          "capabilities": [
            "tools",
            "streaming"
          ]
        }
      },
      "discoveredModelIds": [
        "ocg/deepseek-flash",
        "ocg/deepseek-v4-flash"
      ]
    }
  }
}
```


---

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
