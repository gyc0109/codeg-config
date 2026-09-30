# agent 版本基线（2026-09-30 升级后）

| agent | 版本 | 分发 | 备注 |
| --- | --- | --- | --- |
| pi | 0.0.34 | npx | 升级会覆盖 `dist/index.js`，需重跑 `pi-acp-provider-label-patch` |
| claude_code | 0.84.0 | npx | |
| open_code | 1.18.33 | binary | 二进制在 `~/.local/share/codeg/acp-binaries/opencode/<ver>/` |
| deepseek | 0.9.0 | npx | 已是最新 |
| hermes | 0.21.5 | npx | |
| code_buddy | 2.160.0 | npx | **升级后需重建 symlink**（见下） |
| kimi_code | 2.1.1 | npx | |
| codex | 2.0.1 | npx | 内含 codex-cli 0.159.2，config.toml 格式兼容 |
| cline | 3.0.66 | npx | |
| qoder | 1.1.65 | npx | 升级后 `openclaw gateway restart` |
| cursor | 2026.09.28-64d2043 | binary | 二进制在 acp-binaries/cursor/<ver>/ |
| grok | 1.0.44 | npx | |
| qoder | 1.1.65 | npx | 升级会丢 symlink，需按 bin 重建 |
| cursor | 2026.09.28-64d2043 | binary | 升级后需手动同步 agent_setting |
| antigravity | 1.2.1 | binary | 无新版 |

## 升级踩的坑

1. **npm 升级会丢全局 symlink**：包还在，但 `/usr/bin/<cmd>` 消失，
   codeg 会判定「agent 未安装」。code_buddy、claude-agent-acp 都出现过。
   修复：按 `package.json` 的 `bin` 重建 symlink。
2. **opencode 的 binary 升级不会自动同步 codeg 的 `installed_version`**，
   需要手动 `UPDATE agent_setting`。
3. **pi 升级会冲掉补丁**：`pi-acp-provider-label-patch` 已挂到 codeg 的
   systemd drop-in，重启 codeg 会自动重打；也可手动执行。

## opencode 的 provider 命名空间

provider key 直接用 `ocg` / `ccg`，模型键用真实 model id，于是 ACP 上报的 value
就是 `ocg/<id>` / `ccg/<id>`（两段），和其它 agent 的命名空间一致。

`disabled_providers: ["opencode-go"]` 用来屏蔽内置目录——opencode 会把 models.dev 的
内置模型和 config 里的模型**合并**，不屏蔽的话同一个模型会出现两份（带前缀 / 不带前缀），
而 UI 显示文字完全一样、无法分辨。

**Zen（OpenCode Zen）无法加前缀**：它的 free tier 有服务端校验
`FreeTierError: OpenCode's free tier can only be used from within OpenCode`。
裸 curl、伪造完整 User-Agent（`opencode/1.18.33 ai-sdk/provider-utils/4.0.23 runtime/bun/1.3.14`）、
伪造 `x-session-id` / `x-session-affinity` 头全部被拒。所以只能保留内置 `opencode`
provider（分组显示名 "OpenCode Zen"，模型名无前缀）。另外该账号余额为 0，
只有免费模型（big-pickle）能用，付费模型报 Insufficient account funds。
