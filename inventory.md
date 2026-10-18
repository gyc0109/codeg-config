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

### ⚠️ 别只盯 `acp-binaries`：agent 自己家里也藏旧二进制

`acp-binaries` 只是 **binary 分发**那三个的缓存。**npx 分发的 agent 会往自己的
`~/.<agent>/bin/` 里塞带版本号的二进制，升级时**不删旧的**。2026-10-18 就漏了一个：

```
/root/.grok/bin/grok-1.0.60   183M   ← 升级到 1.0.62 后仍然躺着
/root/.grok/bin/grok-1.0.62   183M
/root/.grok/bin/grok         -> grok-1.0.62
```

按 `acp-binaries` 那套清完以为干净了，实际还有 183M。**清理时所有带版本号的 agent
二进制都要扫一遍**，判断依据是符号链接指向 + 有没有进程/配置引用：

```bash
# 全盘找 ≥20M 的 agent 二进制，看有没有同名多版本
for d in /root/.local/bin /root/.grok /root/.qoder /root/.kimi-code /root/.codex \
         /root/.openclaw /root/.pi /root/.hermes /root/.codebuddy /root/.cline; do
  [ -d "$d" ] && find "$d" -maxdepth 2 -type f -size +20M
done
# 删前两条都过一遍：readlink -f 确认链接指向别处、ps/grep 确认无引用
```

### 日志：本机 `logrotate` 根本没装

`/etc/logrotate.d/nginx` 是有的，但 **`logrotate` 二进制不存在**（`command not found`），
所以 nginx 日志从装上起就没轮转过 —— 2026-10-18 发现 `access.log` 已经涨到 67M，
目录里连一个 `.1` / `.gz` 都没有。litellm 同理，压根没有轮转配置。

手工归档 + 截断（nginx 和 litellm 都持有 fd，**截断是安全的，不用重启**）：

```bash
ARC=/root/codeg-work/log-archive-$(date +%Y%m%d); mkdir -p "$ARC"
gzip -c /var/log/nginx/access.log > "$ARC/nginx-access.log.gz"; : > /var/log/nginx/access.log
gzip -c /var/log/litellm.log     > "$ARC/litellm.log.gz";     : > /var/log/litellm.log
```

要根治就 `apt install logrotate`（配置已经现成，装上即生效）。

### 2026-10-18 实测各轮体积

| 项目 | 清理前 | 释放 |
| --- | --- | --- |
| 旧 binary（antigravity 1.4.0 / cursor 2026.10.14 / opencode 1.19.1） | 3.5G | **1.75G** |
| journal | 134M | 125M |
| nginx + litellm 日志 | 79M | 72M（归档 3.3M 留档） |
| apt / npm 缓存、/tmp | — | 约 150M |
| codeg-work 历次备份 | 19M | 19M |

合计约 **2.1G**。

**刻意留着没删**：`/usr/local/bin/codeg-server.bak`(83M)、
`/usr/local/share/codeg/web.bak`(117M) —— 这俩是 codeg 核心组件唯一的回滚点，
不是缓存，磁盘不紧张时不该动。
