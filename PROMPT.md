# 通用提示词：在新机器上配置 / 更新 codeg 的 agent 与模型

> 直接整段复制给目标机器上的 AI agent（Claude Code / codex / 任何能跑 shell 的 agent）。
> 把顶部的 `<...>` 占位符换成实际值再发。

---

## 提示词正文

```
read https://raw.githubusercontent.com/gyc0109/codeg-config/main/PROMPT-ONBOARD.md
然后按里面的步骤，在这台机器上配置 / 更新 codeg 的 agent 与模型。

补充信息：
- 这台机器的角色：<新机器 / 服务器 / Mac>
- 现有 codeg 是否已在跑：<是 / 否，路径是 ...>
- 我是否已有各供应商的 key：<有，在 ... / 没有，需要我给>
- 允许你改的范围：<全部 / 只改配置文件，别动服务 / 先给我看方案>

要求：
1. 动手前先完整盘点现状并给我看结果
2. 所有写操作前先备份
3. 改完必须实测验证（不能只看配置文件就说好了）
4. 每一步报告进度，遇到你不确定的先问我
```

---

## 或者：只要「更新模型」这一件事

```
read https://raw.githubusercontent.com/gyc0109/codeg-config/main/PROMPT-REFRESH-MODELS.md
按它的流程，在这台机器上刷新 codeg 各 agent 的模型清单。

这台机器用的是：<codeg 自建代理 / LiteLLM / 其他>
供应商 key 在：<...>

重要：这台机器的账号可能和别的机器权限不同，模型列表必须在本机实测，
不要照抄仓库里的清单。改完给我实测结果。
```
