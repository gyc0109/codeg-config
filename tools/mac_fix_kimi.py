#!/usr/bin/env python3
"""修正 Mac kimi 配置里每个 provider 段的失效 default_model。"""
import os
import re
import shutil
import time

P = os.path.expanduser("~/.kimi-code/config.toml")
shutil.copy2(P, P + ".bak." + str(int(time.time())))

FIX = {
    "opencode-go": "longcat-2.5-preview-free",
    "commandcode": "stealth/glyph-cluster:free",
}

lines = open(P).read().splitlines(keepends=True)
out = []
cur = None
changed = []
for ln in lines:
    m = re.match(r"^\[providers\.([a-z0-9-]+)\]", ln)
    if m:
        cur = m.group(1)
    if re.match(r"^default_model\s*=", ln) and cur in FIX:
        old = ln.strip()
        new = 'default_model = "%s"\n' % FIX[cur]
        out.append(new)
        changed.append(f"{cur}: {old} -> {new.strip()}")
        continue
    out.append(ln)

open(P, "w").write("".join(out))
for c in changed:
    print("  ✓", c)
print(f"  共改 {len(changed)} 处")
