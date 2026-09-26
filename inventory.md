# Agent 对照表

生成时间：2026-09-25（数据来自 codeg `/api/acp_list_agents` 与 `/api/list_model_providers`）

> 版本列为「已安装 / codeg registry」。标注 `ahead` 的表示本地版本比 registry 新，
> codeg registry 尚未收录，**不要降级**。

| Agent | 分发 | 已安装 | registry | 链路 | 默认模型 |
| --- | --- | --- | --- | --- | --- |
| `antigravity` | binary | 1.2.1 / 1.2.1 | — | - |
| `claude_code` | npx | 0.81.1 / 0.81.1 | LiteLLM :4000 → :8899 | `deepseek-v4.1-flash` |
| `cline` | npx | **3.0.65** / 3.0.64 | :8899 | - |
| `code_buddy` | npx | 2.157.0 / 2.157.0 | — | - |
| `codex` | npx | 1.13.1 / 1.13.1 | LiteLLM :4000 → :8899 | - |
| `cursor` | binary | 2026.09.18-9a7762b / 2026.09.18-9a7762b | — | - |
| `deepseek` | npx | 0.9.0 / 0.9.0 | :8899 | `deepseek-flash` |
| `gemini` | npx | 0.60.0 / 0.60.0 | :8899（未接） | - |
| `grok` | npx | 1.0.41 / 1.0.41 | :8899 | `space-bunny-free` |
| `hermes` | npx | 0.21.4 / 0.21.4 | :8899 | - |
| `kimi_code` | npx | 2.1.0 / 2.1.0 | :8899 | `space-bunny-free` |
| `open_claw` | npx | **2026.9.5** / 2026.9.4 | — | - |
| `open_code` | binary | 1.18.32 / 1.18.32 | :8899 | `space-bunny-free` |
| `pi` | npx | 0.0.33 / 0.0.33 | :8899 | `space-bunny-free` |
| `qoder` | npx | 1.1.62 / 1.1.62 | — | - |

## Claude Code 槽位映射

Claude Code 只认 Anthropic 协议，经 LiteLLM 转换后可用全部 chat 模型。槽位对应关系：

| 槽位 | 环境变量 | 模型 | 成本 |
| --- | --- | --- | --- |
| 主模型 | `ANTHROPIC_MODEL` | `deepseek-v4.1-flash` | $0.15/$0.6 |
| 推理(thinking) | `ANTHROPIC_REASONING_MODEL` | `space-bunny-free` | 免费 |
| Haiku | `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `glm-5.3-flash` | $0.15/$0.5 |
| Sonnet | `ANTHROPIC_DEFAULT_SONNET_MODEL` | `mimo-v2.6-flash` | $0.14/$0.28 |
| Opus | `ANTHROPIC_DEFAULT_OPUS_MODEL` | `qwen3.8-max` | $2/$6 |
| 自定义项 | `ANTHROPIC_CUSTOM_MODEL_OPTION` | `space-bunny-free` | 免费 |

> `CLAUDE_CODE_AUTO_MODE_SERVER=0` 用于关掉 Claude Code 的服务端正路提示（网关做了协议转换，
> 不满足其透传要求）。不影响功能，仅影响分类器请求是否计费。

## 无法接入 opencode-go 的 agent

以下 agent 走各自厂商私有后端，没有 base URL 覆盖入口，只能用自家凭据：

`gemini`、`code_buddy`、`qoder`、`cursor`、`antigravity`、`open_claw`

## 磁盘清理

binary 缓存升级后会残留旧版本，定期清理：

```bash
# 查看各 agent 已缓存的版本
for d in /root/.local/share/codeg/acp-binaries/*/; do
  echo "$(basename $d):"; ls -1 $d
done

# 删除非当前版本（务必先确认 codeg 里显示的 installed_version）
rm -rf /root/.local/share/codeg/acp-binaries/<agent>/<旧版本目录>
```
