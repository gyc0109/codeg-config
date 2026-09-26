#!/usr/bin/env python3
"""从 codeg 的 SQLite 导出配置类表为 JSON（自动脱敏）。

只导出**配置**，不导出用户数据：
  ✓ agent_setting / model_provider / app_metadata / chat_channel / folder
  ✗ conversation / chat_channel_message_log / token_usage_* / work_task

codeg 未运行时可直接读库；运行中通过 sqlite 只读模式读（能拿到一致快照）。
用法：sudo ./export.sh [输出目录]
"""
import json
import os
import re
import sqlite3
import sys

DB = os.environ.get("CODEG_DB", "/root/.local/share/codeg/codeg.db")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "codeg-app")

EXPORT_TABLES = {
    "agent_setting": "agent_setting.json",
    "model_provider": "model_provider.json",
    "app_metadata": "app_metadata.json",
    "chat_channel": "chat_channel.json",
    "folder": "folder.json",
}

# 整列强制脱敏（值是凭据，不看内容一律替换）
SECRET_COLUMNS = {"token", "access_token", "refresh_token", "api_key", "secret", "password"}
# key 名命中即脱敏
SECRET_KEY_RE = re.compile(
    r"(web_service_token|api_?key|access_?token|refresh_?token|^token$|secret|password|private_key|credential)",
    re.I,
)
# app_metadata 这类 key/value 宽表：命中敏感 key 的行，其 value 整体脱敏
KV_SECRET_KEY_RE = re.compile(
    r"(web_service_token|api_?key|access_?token|refresh_?token|secret|password|private_key|credential|account)",
    re.I,
)
# 值长得像凭据
SECRET_VALUE_RE = re.compile(
    r"\b(sk-[A-Za-z0-9_\-]{16,}|gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{20,})\b"
)
# codeg 自己的 service token 形如 Gyc-xxxxxxxxxxxx
CODEG_TOKEN_RE = re.compile(r"\bGyc-[A-Za-z0-9_\-]{8,}\b")
REDACTED = "${REDACTED}"


def scrub_row(row):
    """脱敏单行：处理 key/value 宽表，以及普通列。"""
    if isinstance(row, dict) and "key" in row and "value" in row:
        if KV_SECRET_KEY_RE.search(str(row.get("key", ""))):
            row["value"] = REDACTED
        else:
            row["value"] = scrub(row["value"], "value")
    for k, v in row.items():
        if SECRET_KEY_RE.search(str(k)):
            row[k] = REDACTED
        elif k not in ("key", "value"):
            row[k] = scrub(v, k)
    return row


def scrub(obj, parent_key=""):
    """递归脱敏。"""
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            if SECRET_KEY_RE.search(str(k)):
                out[k] = REDACTED
            else:
                out[k] = scrub(v, k)
        return out
    if isinstance(obj, list):
        return [scrub(v, parent_key) for v in obj]
    if isinstance(obj, str):
        return CODEG_TOKEN_RE.sub(REDACTED, SECRET_VALUE_RE.sub(REDACTED, obj))
    return obj


def main():
    if not os.path.exists(DB):
        print(f"✗ 找不到 {DB}")
        return 1
    os.makedirs(OUT, exist_ok=True)
    db = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row

    total = 0
    for table, fname in EXPORT_TABLES.items():
        try:
            rows = [dict(r) for r in db.execute(f"select * from {table}")]
        except sqlite3.Error as e:
            print(f"  ⚠ 跳过 {table}: {e}")
            continue
        cleaned = [scrub_row(r) for r in rows]
        path = os.path.join(OUT, fname)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(cleaned, f, ensure_ascii=False, indent=2)
        print(f"  ✓ {table:16} {len(rows):>3} 行 → {fname}")
        total += len(rows)

    # skills 清单（codeg 托管的技能，含来源）
    skills_root = "/root/.codeg/skills"
    if os.path.isdir(skills_root):
        names = sorted(os.listdir(skills_root))
        with open(os.path.join(OUT, "skills.json"), "w", encoding="utf-8") as f:
            json.dump(names, f, ensure_ascii=False, indent=2)
        print(f"  ✓ {'skills':16} {len(names):>3} 个 → skills.json")

    print(f"\n共导出 {total} 行配置到 {OUT}")
    print("提醒：还原配置表需要停止 codeg（restore.sh 已处理）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
