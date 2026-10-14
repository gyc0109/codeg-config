你是这台服务器上的运维 agent。请执行「每周模型与 agent 版本巡检」，并给出简报。

## 你要做的三件事

### 1. 刷新四家供应商的模型清单

```bash
cd /root/codeg-work
python3 refresh_models.py
```

这个脚本会：
- 从 ~/.codeg-models/ 读取上次实测的模型清单
- 重建 LiteLLM (/opt/litellm/config.yaml) 与各 agent 的模型配置
- 覆盖 pi / kimi / hermes / opencode / code_buddy / open_claw / dsh / codex / cline

**注意：脚本已知有两个坑，每次跑完请检查并手动修：**
1. **LiteLLM 的 YAML 锚点**：`&id001` 只能在第一条定义，脚本有时会写成每条都定义，
   导致 `found duplicate anchor`。跑完必须验证：
   `python3 -c "import yaml;yaml.safe_load(open('/opt/litellm/config.yaml'))"`
   如果报错，参考 /root/Labs/codeg-config/tools/refresh-models.py 里的干净重建逻辑修。
2. **open_claw 的默认模型**：脚本会把 `agents.defaults.model` 清成 null。
   跑完检查 `/root/.openclaw/openclaw.json` 的 `agents.defaults.model.primary`，
   应该是 `ocg/longcat-2.5-preview-free`，是 null 就改回来。

### 2. 重新探测模型可用性（本机 key，不能照抄别处）

```bash
cd /root/codeg-work
# OCG
curl -sS https://opencode.ai/zen/go/v1/models \
  -H "Authorization: Bearer $(grep -oP 'OPENCODE_GO_API_KEY=\K\S+' /etc/opencode-go-proxy.env)" \
  -H 'x-opencode-session: probe' > ocg_models_new2.json
# CC
curl -sS https://api.commandcode.ai/provider/v1/models \
  -H "Authorization: Bearer $(grep -oP 'COMMANDCODE_API_KEY=\K\S+' /etc/commandcode-proxy.env)" > cc_models_new2.json
```

对比新旧列表，**重点看差集**：新增了什么、下线了什么。
供应商账号权限可能变化（历史上同一供应商两台机器能差 6 个模型）。

然后全量实测：
- OCG：每个模型分别打 `/chat/completions` 和 `/responses`
- CC：先按 `supported_endpoints` 分协议，再逐个打 `/chat/completions` 判套餐
  （`MODEL_NOT_IN_PLAN` = 套餐外；`Model not exist` / `Authentication failed` = 本机账号无权限）
- 更新 ocg_final_new.json / cc_final_new.json

**模型下线后必须全盘搜引用**，历史踩过的位置：
- ~/.pi/agent/settings.json 的 defaultModel
- ~/.kimi-code/config.toml 里**每个 [providers.*] 段各自的 default_model**
- codeg DB 的 model_provider 表 model 字段、agent_setting 的 env_json 里 *_MODEL
- ~/.openclaw/openclaw.json 的 agents.defaults.modelPolicy.allow
- ~/.cline/data/settings/models.json

### 3. 检查 codeg 里的 agent 有没有新版本

```bash
TOKEN=$(grep '^CODEG_TOKEN=' /etc/codeg.env | cut -d= -f2)
DB=/root/.local/share/codeg/codeg.db
sqlite3 -separator '|' "$DB" "SELECT agent_type,COALESCE(installed_version,'-'),registry_id FROM agent_setting ORDER BY sort_order;" \
| while IFS='|' read -r at ver rid; do
    at=$(echo "$at" | tr -d '"')
    latest=$(curl -sS --max-time 40 -X POST http://127.0.0.1:3080/api/acp_fetch_agent_latest_release \
      -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
      -d "{\"registryId\":\"$rid\",\"agentType\":\"$at\"}" 2>/dev/null \
      | python3 -c "import sys,json
try: print(json.load(sys.stdin).get('version') or '-')
except: print('-')")
    [ "$latest" != "-" ] && [ "$latest" != "$ver" ] && echo "可升级: $at $ver -> $latest"
  done
```

**只报告，不要自动升级。** 升级要人确认（npm 升级会丢 symlink、二进制升级不会同步
DB 版本、pi 升级会覆盖补丁），列出来让我决定。

## 4. 验证（不验证不算做完）

```bash
# 四条代理链路
for m in ocg/longcat-2.5-preview-free ccg/stealth/glyph-cluster:free ds/deepseek-flash ark/doubao-seed-2-1-pro-260915; do
  curl -sS --max-time 90 http://127.0.0.1:4000/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"$m\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply exactly: PONG\"}],\"max_tokens\":2000}"
done

# agent 端到端
cd /root/codeg-work
for a in pi claude_code open_code deepseek hermes code_buddy kimi_code codex cline open_claw grok; do
  cmd=$(python3 -c "import json;print(' '.join(json.load(open('verify/agents.json'))['$a']['cmd']))")
  timeout 300 python3 verify/acp_test.py "$a" $cmd 2>&1 | grep -E '^(OK|FAIL)' | head -1
done
```

## 5. 同步仓库

配置变了就更新 https://github.com/gyc0109/codeg-config（先脱敏 key，`${...}` 占位符）。
推送前检查有没有把真实 key 提交上去。

## 简报格式

```
## 模型变化
OCG:  N -> M   (+新增 / -下线)
CCG:  N -> M
ds/ark: 不变 / ...

## 修掉的失效引用
<文件 -> 从什么改成什么>

## agent 版本
<可升级的列出来；没有就说"全部最新">

## 验证
代理链路: 4/4
模型:     N/M（失败逐条 + 原因是上游限流还是配置问题）
agent:    N/M

## 需要你决定的
<不确定的地方>
```

**遇到不确定的先问，不要自己猜着改。**
