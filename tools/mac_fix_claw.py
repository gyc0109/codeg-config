#!/usr/bin/env python3
"""修正 open_claw 的默认模型：cherry-* 已失效 -> 用 codeg 代理的 ocg。

保留用户的 cherry-* provider（不动），只改 defaults.model.primary。
"""
import json
import os
import shutil
import time

H = os.path.expanduser("~")
P = f"{H}/.openclaw/openclaw.json"
d = json.load(open(P))

bk = P + ".bak." + str(int(time.time()))
shutil.copy2(P, bk)
print(f"  备份: {bk}")

ag = d["agents"]
defaults = ag.setdefault("defaults", {})

old = defaults.get("model")
print("  旧 model:", json.dumps(old, ensure_ascii=False))

TARGET = "ocg/longcat-2.5-preview-free"
if isinstance(old, dict):
    old["primary"] = TARGET
    # 清掉指向失效 provider 的 fallback
    defaults["model"] = {"primary": TARGET}
else:
    defaults["model"] = {"primary": TARGET}

print("  新 model:", json.dumps(defaults["model"], ensure_ascii=False))
print("  providers:", list(d["models"]["providers"].keys()))
print("  modelPolicy.allow 数量:", len((defaults.get("modelPolicy") or {}).get("allow") or []))

json.dump(d, open(P, "w"), indent=2, ensure_ascii=False)
os.chmod(P, 0o600)
print("  ✓ 已写入")
