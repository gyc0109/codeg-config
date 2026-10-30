# agent 版本基线（2026-10-30 升级后）

| agent | 版本 | 分发 | 备注 |
| --- | --- | --- | --- |
| pi | 0.0.34 | npx | 升级会覆盖 `dist/index.js`，需重跑 `pi-acp-provider-label-patch` |
| claude_code | 0.99.1 | npx |  |
| open_code | 2.2.0 | binary | 二进制在 `~/.local/share/codeg/acp-binaries/opencode/<ver>/`，见下「升级踩的坑」第 2 条 |
| deepseek | 0.9.0 | npx | 已是最新 |
| hermes | 0.22.2 | npx |  |
| code_buddy | 2.177.1 | npx | 升级**偶发**丢 symlink，需按 `package.json` 的 bin 重建 |
| kimi_code | 2.4.0 | npx |  |
| codex | 2.5.0 | npx | 内含 codex-cli 0.164.0；**config.toml 的 model 必须带 provider 前缀**，见下 |
| cline | 3.0.74 | npx |  |
| open_claw | 2026.10.4 | npx | **本地超前** registry(2026.9.8)，勿降级；升级后 `openclaw gateway restart` |
| gemini | 0.64.0 | npx | **本地超前** registry(0.60.0)，勿降级；无 Gemini key，暂不可用 |
| grok | 1.0.70 | npx |  |
| qoder | 1.1.81 | npx | 升级**偶发**丢 symlink，需按 bin 重建 |
| cursor | 2026.10.22-27dcf5f | binary | 升级后核实 `agent_setting` |
| antigravity | 1.4.4 | binary | 见下「antigravity 必须带 `--uid=` 启动」 |
| kiro | 2.36.0 | system | 官方安装脚本装到 `~/.local/bin`，需软链到 `/usr/local/bin`，见下 |
| zcode | 0.79.1 | npx | **只是桥，缺后端**：npm 包 `zcode-acp-server`，命令 `zcode-acp`，见下 |

registry 里另有 `command_code`（npx，1.88.0）、`trae`（system）和 2026-10-29 新冒出来的
`minimax_code`（system）三个条目，本机**未安装**。
两者的 `available` 都报 `true`（codeg 只按 registry 判断），实际没用起来。

## antigravity 必须带 `--uid=` 启动

`agy_acp_server.par` 是 Google 的 init 库（`init_google.cc`）构建的，**以 root 运行时会自动
切到 `nobody` 用户/组**，而 Debian 只有 `nogroup`，于是直接崩：

```
F1017 ... init_google.cc:394] Check failed: LookupGIDByGroupName(groupname, &new_gid)  Group nobody not found
```

**codeg 自己会传参数，不用管**。它的注册表里 antigravity 的启动命令是
`agy_acp_server --uid=`（二进制里 `agy_acp_server` / `--uid=` / `Google Antigravity`
是连着存的）。`--uid` 的语义见 `--helpfull`：

```
--uid: [C++] If root, switch to this user id (or empty-string not to switch)
  (default: 'nobody')
```

空串 = 不提权，所以 `--uid=` 正好绕开。

**踩坑提醒**：手工用 ACP 复现 antigravity 时**必须自己带上 `--uid=`**，否则会看到
「Group nobody not found」而误判成「环境缺 nobody 组」。2026-10-17 我就这么误判过一次，
还建了个 `nobody` 组——后来发现是测试命令漏参数，组已删回。**别去 `groupadd nobody`**。

（`--uid=0 --gid=0` 不行，它按**组名**查，会报 `Group 0 not found`。）

启动后 initialize 能正常返回能力集与 5 种认证方式：

| methodId | 说明 | 能否 headless |
| --- | --- | --- |
| `gateway` | 自定义 AI API Gateway，要 `AGY_LLM_GATEWAY_URL` | ✅ **本机就是靠它通的，见下** |
| `gemini-api-key` | 要 `GEMINI_API_KEY` 环境变量 | ✅ 有 key 的话最省事 |
| `oauth-personal` | Google 账号登录 | ⚠️ 会起本地服务 `127.0.0.1:59529` 等浏览器回调，需 SSH 端口转发 |
| `oauth-business` | Gemini Enterprise | 要 GCP project/location |
| `agent-platform` | Gemini Enterprise Agent Platform | 同上 |

认证方式也可写进 `/root/.gemini/antigravity-acp/settings.json` 的 `auth.type`。
该文件默认不存在（本机为空目录），所以 `session/new` 会报
`Authentication required ... no auth method was selected`。

**2026-10-25：用 `gateway` 走本地 litellm，已实测跑通（PONG）**，不需要任何 Google 账号：

```json
// /root/.gemini/antigravity-acp/settings.json
{ "auth": { "type": "gateway" } }
```

```bash
# 写进 codeg 的 agent_setting.env_json（和 claude_code/codex 用同一个机制）
# 注意：不带 /v1！
AGY_LLM_GATEWAY_URL=http://127.0.0.1:4000
```

**`/v1` 是这条路上唯一的坑**：它自己会拼 `/v1/chat/completions`，写成
`http://127.0.0.1:4000/v1` 会 404（`{"detail":"Not Found"}`）。之前用
`http://127.0.0.1:4000/v1` 试过一次，误以为是「网关不支持」而放弃。

模型 id 要用**裸 id**（`ocg/glm-5.3-flash`），不要 codebuddy 那种
`custom-local:` 前缀，否则报
`Model 'custom-local:ocg/beam-free' is not available for the current authentication method`。

**2026-10-18 复测：卡点已经后移了一格。** 带上 `--uid=` 之后 `initialize` 能正常过，
失败点移到 `session/new` 的凭据缺失：

```
session/new: {'code': -32000, 'message': 'Authentication required',
  'data': {'message': "No authentication method selected. Either call the
  `authenticate` method (supports oauth-personal, gemini-api-key,
  agent-platform), or set `auth.type` in settings.json ..."}}
```

而 2026-10-17 那轮是 `initialize: no response`。**这是两个不同的故障，别混为一谈**：
`--uid=` 解决的是「根本起不来」，剩下这个「缺凭据」得配 `auth.type` 或
`GEMINI_API_KEY` 才能通。

三个 binary agent 里，`open_code` 已实测握手跑通（PONG）；`antigravity` 2026-10-25
用 `gateway` 通了；`cursor` 仍卡在 `agent login`（从没登录过，不是升级弄坏的）。

## codex 的 `model` 必须带 provider 前缀（2026-10-29 发现）

`~/.codex/config.toml` 里 codeg 会写成：

```toml
model = "gpt-6-luna"          # 裸名
model_provider = "litellm-bridge"
```

codex 会**原样**把 `model` 发给 `/v1/responses`，而 litellm 只认带前缀的模型名，
于是每次请求都返回：

```
/responses: Invalid model name passed in model=gpt-6-luna.
Call `/v1/models` to view available models for your key.
```

注意 ACP 层面 **不会报错**，`session/prompt` 正常 `end_turn`，错误只是作为一条
`agent_message_chunk` 文本吐出来——所以只看「有没有回复」会误判成成功。

修法是把 `model` 换成带前缀的 id（`ocg/gpt-6-luna` 或 `ccg/gpt-6-luna`），实测 PONG：

```toml
model = "ocg/gpt-6-luna"
```

- codeg 里 codex 的模型目录（`~/.codex/codeg-model-catalog.json`）用的是**裸 slug**
  （`gpt-6-luna`、`deepseek-flash`…共 14 个），`meta.json` 的 `defaultModel` 也是裸名，
  所以 codeg 写出来的 `model` 天生就是错的。
- 直接改 `config.toml` 在 `acp_list_agents` / `acp_detect_agent_local_version` 之后**不会被覆写**；
  但**升级 codex 本身会重新生成 `config.toml`**（2026-10-30 从 2.3.0 升到 2.5.0 时又变回裸名），
  在 codeg 界面里改 codex 的模型设置同理。**每次升级 codex 之后都要重新改一遍**。
- 同一个裸 slug 在 litellm 里往往同时有 `ocg/` 和 `ccg/` 两个同名模型，**挑哪个要按上游**，
  不能盲目批量加别名。

## kiro / qoder 的登录都能 headless 走

两个都不需要图形界面，只是需要你点一下浏览器：

```bash
# kiro：官方就为 headless 准备了 device flow
kiro-cli login --license free --use-device-flow
#   --license free = Builder ID / Google / GitHub 登录
#   --license pro  = Identity Center（要 --identity-provider 与 --region）

# qoder：直接打印链接然后等你在浏览器授权
qoder login
```

`qoder login` 会输出一个 `https://qoder.com/device/selectAccounts?...` 的 URL 并挂起等待，
所以要在能保持会话的终端里跑（tmux / screen），别用一次性 exec。

## 新会话会继承上一次的模型（模型下线后会炸）

ACP 的 `session/new` 不带模型时，agent 会沿用**上一次用过的模型**。2026-10-24 下线
`longcat-2.5-preview-free` 之后，code_buddy 的新会话还拿着它，报：

```
invalid_request_error: /chat/completions: Invalid model name passed in
model=ocg/longcat-2.5-preview-free. Call /v1/models to view available models for your key.
```

**这不是升级搞坏的**，是模型下线的余波，表现为两种情况：

- codeg UI 里选了模型 → 走 `session/set_model`，没事
- 裸跑 ACP（不选模型）→ 继承旧值 → 报错

排查入口：`~/.codebuddy/logs/<日期>/*.log` 里
`getModelsInfo: sessionId=..., currentModelId=...` 就是它实际在用的模型。

另外注意各 agent 的 model id 格式**不统一**：
`code_buddy` 要 `custom-local:ocg/xxx`，`kimi_code` 要裸的 `ocg/xxx`，
`antigravity` 也要裸 id。写测试脚本时按各自的 `configOptions` 取值，别写死。

### code_buddy 对 `ocg/beam-free` 不兼容

`agent_setting` 里 code_buddy 配的是 `CODEBUDDY_MODEL=ocg/beam-free`，实测这条组合被上游拒：

```
[unsupported_parameter] Unrecognized request argument supplied: messages[1].agent
```

code_buddy 会在每条 message 里带一个非标准的 `agent` 字段，`ocg/beam-free` 的免费档网关
校验严，直接拒。**同一个二进制换 `ccg/reflection/beam:free` 或 `ocg/glm-5.3-flash` 就正常回话**
（实测 PONG），所以不是装坏了。

2026-10-25 已把 `agent_setting` 里的
`CODEBUDDY_MODEL` 从 `ocg/beam-free` 改成 `ccg/reflection/beam:free`
（仍是免费档），改完实测 PONG。**别再改回 `ocg/beam-free`**。

## 升级踩的坑

1. **npm 升级会丢全局 symlink**：包还在，但 `/usr/bin/<cmd>` 消失，
   codeg 会判定「agent 未安装」。code_buddy、claude-agent-acp 都出现过。
   修复：按 `package.json` 的 `bin` 重建 symlink。
2. **binary 升级的 `agent_setting.installed_version` 同步情况不稳定**：
   最早遇到过 opencode 不自动同步、要手动 `UPDATE agent_setting`；
   但 2026-10-18 那轮（open_code / cursor / antigravity 三个 binary）**全部自动同步**了。
   升级后一律核实一遍，别假定是哪种行为。
3. **pi 升级会冲掉补丁**：`pi-acp-provider-label-patch` 已挂到 codeg 的
   systemd drop-in，重启 codeg 会自动重打；也可手动执行。

> symlink 丢失（第 1 条）是**偶发**不是必现：2026-10-16 那轮丢了，2026-10-17 那轮
> （claude_code / code_buddy / qoder / cline 四个 npm 升级）13 个 symlink 一个没丢；
> 2026-10-18 那轮（claude_code / cline / grok 三个 npm 升级）也没丢；
> 2026-10-25 那轮（code_buddy / qoder / kimi_code / zcode / claude_code 五个）同样没丢。
> 所以升级后**必须逐个 verify**，不能假定会丢、也不能假定不会丢。

> **升级前备份**：`sqlite3 codeg.db ".backup '<bk>/codeg.db'"`（别直接 `cp` 带 `-wal`
> 的库），外加一份 `acp_list_agents` 快照。2026-10-18 那轮存在
> `/root/codeg-work/pre-upg7-20261018-163322/`，升级脚本沿用 `upgrade*.sh` 的编号习惯。

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
   `available: true`。kiro 的 `supports_self_update: true`，可以自己升，
   但**要登录才能用**（`kiro-cli login`，交互式）。

3. **自升级用 `kiro-cli update -y`**（2026-10-25 实测 2.31.1 → 2.34.0）。
   它只替换 `~/.local/bin/kiro-cli`，`/usr/local/bin` 那两条软链不受影响，
   升完 `acp_detect_agent_local_version` 直接报新版本。
   仍建议给 `TMPDIR` 指个有盘的目录，理由同上。

## zcode 只有桥，没有后端

codeg 的注册表条目写的是「Official ZCode runtime via the community ACP bridge」，
但 `acp_prepare_npx_agent` 实际只跑 `npm i -g zcode-acp-server`——**装的是桥，不是运行时**。

这个 `zcode-acp-server` 是第三方项目（[william0wang/zcode-acp](https://github.com/william0wang/zcode-acp)），
它自己 README 的 Requirements 写得很清楚，缺三样：

1. **官方 ZCode CLI**——由 ZCode 桌面版带出来，或放 PATH，或用 `ZCODE_BIN` 指。
   它是 `zcode app-server --stdio` 这个 headless app-server。npm 上**没有**这个包
   （`npm view zcode` 是 0.0.1 的无关包）。
   实际出处：官方站 <https://zcode.z.ai> 的 **Electron 桌面版**（Linux 有 Beta
   deb / rpm / AppImage），CLI 打包在 app 里：
   - macOS `ZCode.app/Contents/Resources/glm/zcode.cjs`
   - Windows `%LOCALAPPDATA%\Programs\ZCode\resources\glm\zcode.cjs`
   - Linux `<解包目录>/opt/ZCode/resources/glm/zcode.cjs`

   解包验过：3.15.3 的 `zcode.cjs` 是 15MB、`zcode 0.16.9`，带 `app-server`
   与 `login [zai|bigmodel]` 子命令；同目录还有 16 个插件。整个 app 610M，
   只要 CLI + 插件那部分的话是 81M。
2. **`~/.zcode/v2/config.json` 凭据**——由 ZCode app 生成，`zcode login` 走
   **浏览器授权**，headless 服务器上没法自动完成。
3. Node ≥ 22（本机 v24.21.0，满足）。

症状（装完桥但没后端）：

```
[zcode-acp] provider-registry: sync threw (ENOENT: ... open '/root/.zcode/v2/config.json')
[zcode-acp] backend: reader exited (spawn failed: zcode not found — install the zcode CLI, put it on PATH, or set ZCODE_BIN)
```

**注意别被误导**：`node_modules` 里那个 `zcode-acp-martty-linux-x64/bin/martty`
（`martty 0.3.1-zcode.1`）**不是后端**，它是个 TUI 客户端（`--agent` 默认 `dsh-acp`）。
把它设成 `ZCODE_BIN` 只会让报错从「zcode not found」变成「backend: reader exited
(stdout closed)」，仍然跑不通。

所以在装上官方 ZCode CLI + 登录之前，**zcode 在 codeg 里是握手正常、一发 prompt 就报
`zcode create failed: ... (backend dead)`**。这条别指望靠 `acp_prepare_npx_agent` 解决。

另外 zcode 是 **GLM 专属 harness**，吃的是 GLM Coding Plan 的包月额度。若本来就没有
该订阅，装了也没有额外收益——`ocg/glm-5.3`、`ccg/z-ai/glm-5.3-flash` 这些已经通了。
2026-10-17 的决定是**不折腾**：桥留着，不去解桌面版、不配凭据。

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
