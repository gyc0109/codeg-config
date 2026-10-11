#!/usr/bin/env python3
"""按 Mac 自己的 CC 套餐重算可用集，并覆盖 ~/.codeg-models/cc_final_new.json。

Mac 的 CC 账号与服务器不是同一个，必须用本机探测结果，不能沿用服务器的。
"""
import json
import os
import shutil
import time

H = os.path.expanduser("~")
M = f"{H}/.codeg-models"

full = json.load(open("/tmp/cc_models.json"))
ms = full.get("data") or []
ep = {m["id"]: set(m.get("supported_endpoints") or []) for m in ms}

res = {}
for ln in open("/tmp/cc_reprobe.txt"):
    p = ln.split()
    if len(p) >= 2:
        res[p[1]] = p[0]

DENIED = {k for k, v in res.items() if v in ("DENIED",)}
BAD = {k for k, v in res.items() if v in ("AUTHFAIL", "NOTEXIST", "ERR")}
BOTH = {k for k, v in ep.items() if v >= {"/chat/completions", "/responses"}}
CHATONLY = {k for k, v in ep.items() if v == {"/chat/completions"}}
MSGONLY = {k for k, v in ep.items() if v == {"/messages"}}

chat_ok = sorted((BOTH | CHATONLY) - DENIED - BAD)
resp_ok = sorted(BOTH - DENIED - BAD)

# messages 侧：只有实测通过 /messages 的才算（Mac 上单独验过 sonnet-5-5）
msg_ok = ["claude-sonnet-5-5", "claude-haiku-5-5"]

old_p = f"{M}/cc_final_new.json"
old = json.load(open(old_p))
print(f"  旧（沿用服务器）: chat {len(old['chat_ok'])} resp {len(old['resp_ok'])}")
print(f"  新（Mac 实测）:   chat {len(chat_ok)} resp {len(resp_ok)}")

shutil.copy2(old_p, old_p + ".srv.bak." + str(int(time.time())))
json.dump({"chat_ok": chat_ok, "resp_ok": resp_ok, "msg_ok": msg_ok,
           "denied": sorted(DENIED), "unavail": sorted(BAD)},
          open(old_p, "w"), indent=1)

print()
print(f"  ➖ Mac 无权限（服务器有）: {sorted(set(old['chat_ok']) - set(chat_ok))}")
print(f"  ➕ Mac 有（服务器无）:     {sorted(set(chat_ok) - set(old['chat_ok']))}")
print()
print(f"  ✓ 已更新 {old_p}")
