# Mac（GYCs-MacBook-Air）维护手册

## 架构（和服务器不同！）

Mac 上有**两个**互不相干的代理，别搞混：

| 端口 | 是什么 | 谁在用 |
| --- | --- | --- |
| **15721** | **cc-switch**（`/Applications/CC Switch.app`） | **claude_code / codex** |
| **15825** | **codeg 自己的 Python 代理**（launchd `app.codeg.opencode-go-proxy`） | pi / kimi / hermes / open_code / code_buddy / grok / open_claw / cline / dsh |

> ⚠️ **cc-switch 是用户自己的工具**，配置在 `~/.cc-switch/`，`~/.claude/settings.json`
> 和 `~/.codex/config.toml` 都由它管。**不要动这两个文件**——它们的 mtime 应该一直
> 停在用户自己上次修改的时间。codeg 代理侧的改动一律只写 `~/.codeg/` 和各 agent 自己的
> 配置（`~/.pi`、`~/.kimi-code` 等）。

## codeg 代理（:15825）

`mac/opencode-go-proxy.py`，4 上游、按前缀分流：

```
ocg/<id>  ->  https://opencode.ai/zen/go
ccg/<id>  ->  https://api.commandcode.ai/provider/v1
ds/<id>   ->  https://api.deepseek.com/v1
ark/<id>  ->  https://ark.cn-beijing.volces.com/api/v3
```

密钥（600 权限，环境变量优先）：

```
~/.codeg/opencode-go-key           # OPENCODE_API_KEY
~/.codeg/commandcode-goat-key      # COMMANDCODE_API_KEY
~/.codeg/deepseek-key              # DEEPSEEK_API_KEY
~/.codeg/ark-key                   # VOLCENGINE_ARK_KEY
```

重启：

```bash
launchctl bootout  gui/$(id -u)/app.codeg.opencode-go-proxy
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/app.codeg.opencode-go-proxy.plist
```

## 环境要点（踩过的坑）

- **Mac 没有 `timeout`**：用 perl 版
  `perl -e 'my $t=shift;my $p=fork();if($p==0){exec @ARGV;exit 127;}local $SIG{ALRM}=sub{kill "TERM",$p;exit 124;};alarm $t;waitpid($p,0);' 60 <cmd>`
- **node 在 fnm 里**：`~/.local/share/fnm/node-versions/v26.8.1/installation/bin`
  （非交互 shell 的 PATH 里没有 node/npm，必须先 export）
- **系统 python 没有 pyyaml**，PEP 668 也挡住了 pip。用现成的 venv：
  `~/.codeg-venv/bin/python`（里面装了 pyyaml 6.0.3）
- **自己并发的负载会压垮机器**：这台 24GB 但并行测试 + 网关重启容易飙到 load 30+
- codeg 的 DB 在 `~/Library/Application Support/app.codeg/codeg.db`
  （注意还有个空的 `~/Library/Application Support/codeg/codeg.db`，不是那个）
- 模型探测结果缓存在 `~/.codeg-models/`

## 常用脚本（tools/）

| 脚本 | 用途 |
| --- | --- |
| `mac_probe_models.sh` | 拉 OCG / CC 的模型列表 |
| `mac_refresh_models.py` | 刷新各 agent 的模型清单（读 `~/.codeg-models/`） |
| `mac_fix_providers.py` | 修 codeg DB 里失效的 provider + 补 ds/ark |
| `mac_fix_claw.py` | 修 open_claw 的默认模型（cherry-* 失效时） |
| `mac_fix_kimi.py` | 修 kimi 各 provider 段里的 `default_model` |
| `mac_verify2.sh` | agent 实测 |

## ⚠️ Mac 的 CC 账号和服务器不是同一个

套餐权限不同，**不能沿用服务器探测的模型清单**。2026-10-11 实测对比：

| | 服务器 CC 账号 | Mac CC 账号 |
| --- | --- | --- |
| chat 可用 | 54 | **50** |
| responses 可用 | 47 | **44** |

Mac 账号**没有**（服务器有）：
`Qwen/Qwen3.6-Max-Preview`（404 model not exist）、
`google/gemini-3.7-flash`、`meta/muse-spark-1.2`、`1.2-contributor`、`1.3`、`1.3-contributor`（均 403 auth failed）

Mac 账号**独有**（服务器无）：
`poolside/laguna-s-2.1-free`、`xiaomi/mimo-v2.5`

所以每次刷新必须在本机跑 `mac_cc_reprobe.sh`，用它的输出重建
`~/.codeg-models/cc_final_new.json`，**不要**直接复制服务器的。

另外 **OCG 的 key 也是两个不同的账号**（服务器 `oc_sk_3bc7...` / Mac `oc_sk_75d5...`），
模型列表目前一致（都 38 个），但也不能假定永远一样。

### 已知不稳的模型

`ccg/inclusionai/ling-3.1-flash:free` —— 免费的，上游经常 `rate_limit_error`。
服务器和 Mac 用各自的 key 都是同样结果，属于上游限流，不是配置问题。

## open_claw 的两个坑

1. `agents.entries` 必须非空（`{"main": {}}`），否则网关起不来、报
   `agents.entries must contain at least one configured agent`。用 `openclaw doctor --fix` 修。
2. doctor 会把 `agents.defaults.models` 迁移成 `agents.defaults.modelPolicy.allow`，
   **之后改 allowlist 要改 `modelPolicy.allow`**，改 `models` 不生效。
   用 `mac_fix_policy.py` 同步。

## pi 的额外依赖

`pi-acp` 只是 ACP 适配器，**还需要主程序 `pi`**，否则 session/new 报
`Could not start pi: executable not found (command: pi)`：

```bash
npm install -g @earendil-works/pi-coding-agent
```
