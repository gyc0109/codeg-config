# codeg 定时任务（automation）

codeg 自带 automation 系统（不是系统 cron），任务和它的执行记录都在 codeg UI 的
自动化面板里可见。

## 已配置的任务

| 项目 | 值 |
| --- | --- |
| 名称 | 每周模型与 agent 版本巡检 |
| 调度 | `0 4 * * 2,4,6` （**周二 + 周四 + 周六 04:00**） |
| 时区 | Asia/Shanghai |
| Agent | `pi` |
| 工作目录 | codeg folder #22 = `/root/Labs/codeg-config` |
| isolation | `shared_in_root`（要改真实配置，不能用 worktree） |

## 任务做什么

1. 跑 `refresh_models.py` 重建各 agent 的模型配置
2. 用**本机 key** 重新探测四家供应商的可用模型（不能照抄别处）
3. 检查 codeg 里的 agent 有没有新版本（**只报告，不自动升级**）
4. 验证四条代理链路 + agent 端到端
5. 同步配置到仓库（脱敏后）

提示词在 `tools/weekly-refresh-prompt.md`。

## 重建任务

```bash
tools/create-weekly-automation.py --cron "0 4 * * 2,4,6" --folder-id 22
```

## API 速查（摸索出来的）

| RPC | 参数 |
| --- | --- |
| `automation_create` | `{draft}` |
| `automation_update` | `{id, ...}` |
| `automation_delete` | `{id}`（软删除，写 `deleted_at`） |
| `automation_set_enabled` | `{id, enabled}` |
| `automation_run_now` | `{automationId}` ← 注意不是 `id` |
| `automation_compute_next_run` | `{cron, timezone}` |

### draft 的完整字段（11 个，全部必填）

```json
{
  "name": "...",
  "enabled": true,
  "trigger_kind": "schedule",
  "cron": "0 4 * * 2,4,6",
  "timezone": "Asia/Shanghai",
  "agent_type": "pi",
  "isolation": "shared_in_root",
  "is_remote_branch": false,
  "root_folder_id": 22,
  "branch": null,
  "config": {
    "action": "launch_session",
    "prompt_blocks": [{"type": "text", "text": "..."}],
    "display_text": "..."
  }
}
```

**坑：**
- `isolation` 只有 `worktree_per_run` 和 `shared_in_root` —— **没有** `in_place`
- `config.action` 是 tagged enum：`launch_session` / `enqueue_task`
- 提示词必须放在 `config.prompt_blocks[].text`，**不是** `config.prompt`
  （写 `prompt` 会报 `validation error: prompt is required`）
- `automation_run_now` 的参数名是 `automationId`，其他接口用 `id`
- `automation_delete` 是软删除，DB 里行还在，查活跃任务要加 `WHERE deleted_at IS NULL`

## DB 结构

```
automation:      id, name, enabled, trigger_kind, cron, timezone, next_run_at,
                 agent_type, root_folder_id, isolation, branch, is_remote_branch,
                 config, last_run_at, last_run_status, last_run_conversation_id,
                 unseen_failures, created_at, updated_at, deleted_at

automation_run:  id, automation_id, status, trigger, scheduled_for, started_at,
                 ended_at, conversation_id, connection_id, worktree_folder_id,
                 stop_reason, error, summary, created_at
```

## 冒烟测试

建个临时任务，`run_now` 触发，看 `automation_run.status` 变成 `succeeded`
且 `conversation_id` 有值，说明链路通。实测 8 秒完成。

```bash
automation_run_now '{"automationId":<id>}'
sqlite3 codeg.db "SELECT status,conversation_id,stop_reason FROM automation_run ORDER BY id DESC LIMIT 1;"
```
