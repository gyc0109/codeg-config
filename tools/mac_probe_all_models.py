#!/usr/bin/env python3
"""Mac：全量探测 codeg 代理上的所有模型（chat 端点）。

与服务器同口径：每个模型单独请求，要求回 PONG。
"""
import json
import os
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

H = os.path.expanduser("~")
PROXY = "http://127.0.0.1:15825/v1/chat/completions"

MODELS = []
try:
    ref = json.load(open(f"{H}/.codebuddy/models.json"))["models"]
    MODELS = [m["id"] for m in ref if m["id"].startswith(("ocg/", "ccg/", "ds/", "ark/"))]
except Exception as e:
    sys.exit(f"读模型清单失败: {e}")

print(f"  待测: {len(MODELS)} 个", flush=True)


def probe(mid):
    fd, path = tempfile.mkstemp()
    os.close(fd)
    payload = json.dumps({"model": mid,
                          "messages": [{"role": "user", "content": "Reply with exactly: PONG"}],
                          "max_tokens": 3000})
    try:
        r = subprocess.run(
            ["curl", "-sS", "--max-time", "150", "-o", path, "-w", "%{http_code}",
             PROXY, "-H", "Content-Type: application/json", "-d", payload],
            capture_output=True, text=True, timeout=180)
        code = r.stdout.strip()
        try:
            d = json.load(open(path))
        except Exception:
            return f"FAIL {mid} [http {code}] 非JSON"
        if isinstance(d, dict) and d.get("error"):
            return f"FAIL {mid} [http {code}] {str(d['error'].get('message',''))[:70]}"
        ch = (d.get("choices") or [{}])[0]
        c = ch.get("message", {}).get("content") or ""
        if "PONG" in c:
            return f"OK   {mid}"
        return f"FAIL {mid} finish={ch.get('finish_reason')} content={c[:40]!r}"
    except Exception as e:
        return f"FAIL {mid} {type(e).__name__}: {str(e)[:50]}"
    finally:
        try:
            os.unlink(path)
        except Exception:
            pass


results = []
with ThreadPoolExecutor(max_workers=4) as ex:
    for r in ex.map(probe, MODELS):
        results.append(r)
        print("  " + r, flush=True)

ok = sum(1 for r in results if r.startswith("OK"))
fail = [r for r in results if not r.startswith("OK")]
print()
print(f"  ══ OK {ok} / FAIL {len(fail)}", flush=True)
if fail:
    print("  ── 失败清单 ──")
    for r in fail:
        print("   " + r)
