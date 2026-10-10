# tools/

## refresh-models.py

四家供应商模型清单的**权威刷新流程**。供应商会不定期上下线模型
（例：2026-10 Command Code 的 `stealth/space-bunny-alpha` free preview 结束），
下线后仍被引用的 agent 会直接报错，所以每次都要重跑。

前置：
- `opencode-go-proxy` / `litellm` / `commandcode-proxy` 在跑
- `/etc/opencode-go-proxy.env`、`/etc/commandcode-proxy.env` 存在
- 探测脚本 `ocg_probe.sh`、`ocg_resp.sh`、`cc_plan_probe.sh` 在 `/root/codeg-work/`

步骤：

1. **重新拉列表并对比**
   ```bash
   # OCG
   curl -sS https://opencode.ai/zen/go/v1/models -H "Authorization: Bearer $OCGKEY" > ocg_models_new.json
   # CC（每个模型带 supported_endpoints，是协议判定的权威来源）
   curl -sS https://api.commandcode.ai/provider/v1/models -H "Authorization: Bearer $CCKEY" > cc_models_new.json
   ```
2. **全量重测**：OCG 分别打 `/chat/completions` 和 `/responses`；
   CC 打 `/chat/completions`（判套餐 + 可用性），Claude 系另打 `/messages`
3. **更新 `ocg_final_new.json` / `cc_final_new.json`**
4. **跑本脚本**重建所有 agent 配置

关键点：

- **Ark 模型名必须带日期后缀**（`doubao-seed-2-1-pro-260915`）；用短名
  `doubao-seed-2-1-pro` 会被上游 400（`Invalid model name`）。
- **LiteLLM 的 `additional_drop_params` 锚点 `&id001` 只能在首条定义**，
  其余用 `*id001`；重复定义报 `found duplicate anchor`，把别名后面接上序列项
  则报 `expected <block end>`。重建后务必 `yaml.safe_load` 验一遍。
- **LiteLLM 的 `ocg/` 必须是 chat ∪ responses 的并集**（cline/code_buddy/grok/
  deepseek 走 chat 端点，codex 走 responses）。
- **CC 的 `stealth/*:free` 是推理模型**，`max_tokens` 给小了会 `finish_reason=length`
  且 `content` 为空——探测时给足 2000。
- 别把备份都命名成 `config.yaml`（litellm 和 hermes 同名会互相覆盖）。
- `ocg/`、`ds/`、`ark/` 的真实 model id 会撞名，前缀不可省。
