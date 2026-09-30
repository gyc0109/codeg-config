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
| open_claw | 2026.9.7 | npx | 升级后 `openclaw gateway restart` |
| gemini | 0.62.0 | npx | 无 Gemini key，暂不可用 |
| grok | 1.0.44 | npx | |
| qoder | 1.1.62 | npx | 已是最新 |
| cursor | 2026.09.18 | binary | 无新版 |
| antigravity | 1.2.1 | binary | 无新版 |

## 升级踩的坑

1. **npm 升级会丢全局 symlink**：包还在，但 `/usr/bin/<cmd>` 消失，
   codeg 会判定「agent 未安装」。code_buddy、claude-agent-acp 都出现过。
   修复：按 `package.json` 的 `bin` 重建 symlink。
2. **opencode 的 binary 升级不会自动同步 codeg 的 `installed_version`**，
   需要手动 `UPDATE agent_setting`。
3. **pi 升级会冲掉补丁**：`pi-acp-provider-label-patch` 已挂到 codeg 的
   systemd drop-in，重启 codeg 会自动重打；也可手动执行。
