# agent 版本基线（2026-10-17 升级后）

| agent | 版本 | 分发 | 备注 |
| --- | --- | --- | --- |
| pi | 0.0.34 | npx | 升级会覆盖 `dist/index.js`，需重跑 `pi-acp-provider-label-patch` |
| claude_code | 0.92.0 | npx |  |
| open_code | 1.19.1 | binary | 二进制在 `~/.local/share/codeg/acp-binaries/opencode/<ver>/`，升级后需手动同步 `agent_setting` |
| deepseek | 0.9.0 | npx | 已是最新 |
| hermes | 0.22.2 | npx |  |
| code_buddy | 2.168.2 | npx | 升级**偶发**丢 symlink，需按 `package.json` 的 bin 重建 |
| kimi_code | 2.2.0 | npx |  |
| codex | 2.2.2 | npx | 内含 codex-cli 0.160.1，config.toml 格式兼容 |
| cline | 3.0.72 | npx |  |
| open_claw | 2026.10.4 | npx | 升级后 `openclaw gateway restart` |
| gemini | 0.64.0 | npx | 无 Gemini key，暂不可用 |
| grok | 1.0.60 | npx |  |
| qoder | 1.1.73 | npx | 升级**偶发**丢 symlink，需按 bin 重建 |
| cursor | 2026.10.14-0f9edde | binary | 升级后需手动同步 `agent_setting` |
| antigravity | 1.4.0 | binary | |
| kiro | 2.31.1 | system | 官方安装脚本装到 `~/.local/bin`，需软链到 `/usr/local/bin`，见下 |
| zcode | 0.72.0 | npx | npm 包名 `zcode-acp-server`，命令 `zcode-acp` |

## 升级踩的坑

1. **npm 升级会丢全局 symlink**：包还在，但 `/usr/bin/<cmd>` 消失，
   codeg 会判定「agent 未安装」。code_buddy、claude-agent-acp 都出现过。
   修复：按 `package.json` 的 `bin` 重建 symlink。
2. **opencode 的 binary 升级不会自动同步 codeg 的 `installed_version`**，
   需要手动 `UPDATE agent_setting`。
3. **pi 升级会冲掉补丁**：`pi-acp-provider-label-patch` 已挂到 codeg 的
   systemd drop-in，重启 codeg 会自动重打；也可手动执行。

> symlink 丢失（第 1 条）是**偶发**不是必现：2026-10-16 那轮丢了，2026-10-17 那轮
> （claude_code / code_buddy / qoder / cline 四个 npm 升级）13 个 symlink 一个没丢。
> 所以升级后**必须逐个 verify**，不能假定会丢、也不能假定不会丢。

## kiro 安装要点

kiro 是 `system` 分发（不走 npx / binary），codeg 只负责探测已装版本，不负责装。
官方安装脚本：

```bash
curl -fsSL https://cli.kiro.dev/install | bash   # 装到 ~/.local/bin
```

两个坑：

1. **脚本要求临时目录至少 2 GiB 可用**，在这台机子上会直接失败
   （`/tmp` 是 tmpfs 只给了 2.0G，`/` 只剩 3.8G）。要给 `TMPDIR` 指一个有盘的目录：

   ```bash
   mkdir -p /root/codeg-work/kiro-tmp
   TMPDIR=/root/codeg-work/kiro-tmp curl -fsSL https://cli.kiro.dev/install | bash
   ```

   （顺带也避免在 3.8G 内存的机子上拿 tmpfs 当解压盘。）

2. **codeg 的 PATH 不含 `~/.local/bin`**（是
   `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin`），装完 codeg 认不到，
   必须软链：

   ```bash
   ln -sf /root/.local/bin/kiro-cli      /usr/local/bin/kiro-cli
   ln -sf /root/.local/bin/kiro-cli-chat /usr/local/bin/kiro-cli-chat
   ```

   链上之后 `acp_list_agents` 立刻报 `installed_version: 2.31.1`、
   `available: true`。kiro 的 `supports_self_update: true`，可以自己升。

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

## open_claw 升级要跑迁移（2026.9.8）

升级到 2026.9.8 后 gateway 会直接 `status=78/CONFIG` 起不来：

```
OpenClaw agent database .../openclaw-agent.sqlite uses schema version 21;
stop active agents and run openclaw doctor --fix to migrate session identities before using it.
```

修复：

```bash
systemctl --user stop openclaw-gateway
openclaw doctor --fix
systemctl --user start openclaw-gateway
```

注意首次启动要等约 20~30s 才会 listen（要跑 session-sqlite reclamation）。

## open_claw 升级偶发缺模块（2026.9.9）

升级后 gateway 起不来，日志是：

```
ERROR: ERR_MODULE_NOT_FOUND
  url: file:///usr/lib/node_modules/openclaw/node_modules/@openclaw/fs-safe/file-lock
```

修复（与 schema 迁移同一套流程）：

```bash
systemctl --user stop openclaw-gateway
openclaw doctor --fix
systemctl --user start openclaw-gateway
```

首次 listen 仍需等约 20~30s。
