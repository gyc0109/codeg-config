## 每周模型巡检（提示词）

你是这台服务器上的运维 agent。请执行「每周模型与 agent 版本巡检」，给出简报。

## ⚠️ 时间预算（重要）

整件事必须在 **20 分钟内**做完。如果某个步骤超时，**跳过它并在简报里说明**，
不要重试、不要死磕。这台机器只有 3.8G 内存，你自己跑的重活会把 load 干到 40+，
反而让后面的检查全超时（历史踩过：卡了 1 小时 40 分还没完）。

**每开始一个耗时步骤前，先看 load：`cut -d' ' -f1 /proc/loadavg`。
如果 load > 5，等 30 秒再看；连续 3 次都 > 5 就跳过这个步骤。**

## 1. 刷新模型配置（必须做）

```bash
cd /root/codeg-work
python3 refresh_models.py
```

脚本会重建 LiteLLM 与各 agent 的模型配置，并**自己校验** YAML 锚点
（`&id001` 只定义一次），非法就报错退出。

跑完确认：
```bash
python3 -c "import yaml;print(len(yaml.safe_load(open('/opt/litellm/config.yaml'))['model_list']))"
python3 -c "import json;print(json.load(open('/root/.openclaw/openclaw.json'))['agents']['defaults']['model'])"
systemctl is-active litellm
```
预期：打印条数 / 打印 `{'primary': 'ocg/longcat-2.5-preview-free'}` / `active`。

## 2. 探测模型可用性（必须做）

```bash
cd /root/codeg-work
OCGKEY=$(grep -oP 'OPENCODE_GO_API_KEY=\K\S+' /etc/opencode-go-proxy.env)
curl -sS --max-time 60 https://opencode.ai/zen/go/v1/models \
  -H "Authorization: Bearer $OCGKEY" -H 'x-opencode-session: probe' > ocg_models_new.json
CCKEY=$(grep -oP 'COMMANDCODE_API_KEY=\K\S+' /etc/commandcode-proxy.env)
curl -sS --max-time 60 https://api.commandcode.ai/provider/v1/models \
  -H "Authorization: Bearer $CCKEY" > cc_models_new.json
```

**跟上一版对比，重点看差集**（新增 / 下线）。账号权限可能变化
（历史：同一供应商两台机器能差 6 个模型）。

然后**只测差集里的模型**，不要全量重测 100 个（太慢）。
- OCG：`/chat/completions` 和 `/responses` 各打一次
- CC：先看 `supported_endpoints` 分协议，再打 `/chat/completions` 判套餐
  （`MODEL_NOT_IN_PLAN`=套餐外；`Model not exist`/`Authentication failed`=账号无权限）
- 全量重测时用**并发 4**，别开 8 以上

模型下线后**必须搜引用**（历史踩过的位置）：
- `~/.pi/agent/settings.json` 的 `defaultModel`
- `~/.kimi-code/config.toml` 里**每个 `[providers.*]` 段各自的 `default_model`**
- codeg DB：`model_provider.model`、`agent_setting.env_json` 里的 `*_MODEL`
- `~/.openclaw/openclaw.json` 的 `agents.defaults.modelPolicy.allow`
- `~/.cline/data/settings/models.json`

## 3. 验证（轻量，别超时）

**只做这两项，总共不超过 3 分钟：**

```bash
# (a) 四条代理链路
for m in ocg/longcat-2.5-preview-free ccg/stealth/glyph-cluster:free ds/deepseek-flash ark/doubao-seed-2-1-pro-260915; do
  printf '%-42s ' "$m"
  curl -sS --max-time 60 http://127.0.0.1:4000/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"$m\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply exactly: PONG\"}],\"max_tokens\":2000}" \
    | python3 -c "import sys,json
try:
    d=json.load(sys.stdin); c=(d.get('choices') or [{}])[0].get('message',{}).get('content','')
    print('OK' if 'PONG' in c else 'FAIL')
except: print('FAIL')"
done

# (b) 两个代表 agent（不是全部 11 个）
cd /root/codeg-work
timeout 120 python3 verify/acp_test.py pi pi-acp 2>&1 | grep -E '^(OK|FAIL)' | head -1
timeout 120 python3 verify/acp_test.py open_code \
  "$(ls -d /root/.local/share/codeg/acp-binaries/opencode/*/ | tail -1)linux-x86_64/opencode" acp 2>&1 \
  | grep -E '^(OK|FAIL)' | head -1
```

**绝对不要跑全量 11 个 agent 的套件**——那个在负载高的机器上会跑 1 小时以上，
而且会因为资源竞争产生一堆假的「超时」失败。

想更全面就先看 load，< 3 才跑，且用 `timeout 90`。

## 4. 同步仓库

配置有变就更新 https://github.com/gyc0109/codeg-config（**先脱敏 key，用 `${...}` 占位符**）。
推送前检查有没有把真实 key 提交上去。

## 简报格式

```
## 模型变化
OCG:  N -> M   (+新增 / -下线)
CCG:  N -> M
ds/ark: 不变 / ...

## 修掉的失效引用
<文件 -> 从什么改成什么；没有就说"无">

## 验证
代理链路: 4/4
代表 agent: 2/2

## 跳过的步骤（如果有）
<哪一步、为什么跳>

## 需要你决定的
<不确定的地方>
```

**遇到不确定的先问，不要自己猜着改。**
