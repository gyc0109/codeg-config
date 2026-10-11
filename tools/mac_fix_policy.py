#!/usr/bin/env python3
"""同步 open_claw 的 modelPolicy.allow 为当前 models 列表。"""
import json
import os
import shutil
import time

H = os.path.expanduser("~")
P = f"{H}/.openclaw/openclaw.json"
d = json.load(open(P))
defaults = d["agents"]["defaults"]
allow = list((defaults.get("models") or {}).keys())
old = list((defaults.get("modelPolicy") or {}).get("allow") or [])

shutil.copy2(P, P + ".bak." + str(int(time.time())))
defaults["modelPolicy"] = {"allow": allow}
json.dump(d, open(P, "w"), indent=2, ensure_ascii=False)
os.chmod(P, 0o600)

print(f"  modelPolicy.allow: {len(old)} -> {len(allow)}")
stale = sorted(set(old) - set(allow))
print(f"  清除的失效项: {stale if stale else '无'}")
newly = sorted(set(allow) - set(old))
print(f"  新增项: {newly[:8]}{' ...' if len(newly) > 8 else ''}")
