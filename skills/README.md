# codeg skill 安装

## 五个来源

| skill | 来源 | 说明 |
| --- | --- | --- |
| `find-skills` | `vercel-labs/skills` | 发现/安装 skill 的元技能 |
| `web-design-guidelines` | `vercel-labs/agent-skills` | UI 代码审查 |
| `skill-creator` | `anthropics/skills` | 创建/评测 skill |
| `frontend-design` | `anthropics/skills` | 前端视觉设计 |
| `brainstorming` | `obra/superpowers` | codeg 自带（experts 包），不用装 |

⚠️ `anthropics/skills` 里这两个在 **`skills/` 子目录**下，不是仓库根目录：
`skills/skill-creator/SKILL.md`、`skills/frontend-design/SKILL.md`

注册中心是 **skills.sh**（不是 GitHub 搜索）。

## 一键装

```bash
tools/install-skills.sh \
  vercel-labs/skills       find-skills \
  vercel-labs/agent-skills web-design-guidelines \
  anthropics/skills        skill-creator \
  anthropics/skills        frontend-design
```

## 目录布局（重要）

codeg 和 skills CLI 的「中央仓库」约定是**相反的**：

```
codeg 约定（本机原有 36 个都这样，也是我们要的统一形态）：
  真内容            ~/.codeg/skills/<name>
  ~/.agents/skills  -> 符号链接 -> ~/.codeg/skills/<name>
  各 agent 目录      -> 符号链接 -> ~/.codeg/skills/<name>

skills CLI 的约定：
  真内容            ~/.agents/skills/<name>
  ~/.codeg/skills   -> 符号链接 -> ~/.agents/skills/<name>
```

所以**用 CLI 装完必须跑 `tools/normalize-skills-layout.py` 归一化**，
否则新老 skill 的指向会不一致，而 codeg 的 `.manifest.json` 和
experts/custom/science/officecli 四套子系统都按「`.codeg/skills` 是真内容」工作。

## 要注意的

- **`npm update skills` 会覆盖 `dist/cli.mjs`**，codeg 补丁失效。
  `tools/patch-skills-cli.py` 改的就是这个文件，升级后重跑即可（幂等）。
- CLI 装的时候会报 `Eve` / `PromptScript` 失败 —— 那两个 agent 不支持全局安装，忽略。
- CLI 只覆盖它认得的 agent 目录。本机实际有 **10 个**：
  `.codeg` `.claude` `.pi/agent` `.codex` `.config/opencode` `.hermes`
  `.kimi-code` `.openclaw` `.agents` `.codebuddy` `.dsh`
  （CLI 认为 pi/codex 读 `~/.agents/skills`，所以不会碰它们的专属目录）
- **skill 列表在会话启动时注入**，装完要开新会话才看得到。
- `~/.codeg/skills/ui-render` 带 `.codeg-managed` 标记，是**有意不分发**的，
  所以主仓库 41 个、各 agent 目录 40 个。
