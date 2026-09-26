#!/usr/bin/env python3
"""把 codeg-app/*.json 里的配置写回 codeg 的 SQLite。

**必须在 codeg 停止后运行**（restore.sh 会先停 codeg）。
只写配置表，不碰 conversation / token_usage 等用户数据。
值里的 ${REDACTED} 占位符会被跳过（保留库中原值），避免用占位符覆盖真实凭据。
"""
import json
import os
import sqlite3
import sys

DB = os.environ.get("CODEG_DB", "/root/.local/share/codeg/codeg.db")
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "codeg-app")

# (表名, 导出文件, 主键列)
TABLES = [
    ("model_provider", "model_provider.json", "id"),
    ("agent_setting", "agent_setting.json", "id"),
    ("app_metadata", "app_metadata.json", "key"),
    ("chat_channel", "chat_channel.json", "id"),
    ("folder", "folder.json", "id"),
]
PLACEHOLDER = "${REDACTED}"
DRY = "--dry-run" in sys.argv


def main():
    if not os.path.exists(DB):
        print(f"✗ 找不到 {DB}")
        return 1
    db = sqlite3.connect(DB)
    db.row_factory = sqlite3.Row

    # 安全闸：codeg 还在跑就别写
    try:
        r = db.execute("select value from app_metadata where key='db_initialized_at'").fetchone()
        if r is None:
            print("✗ 这是个空库，疑似不是 codeg 数据库")
            return 1
    except sqlite3.Error as e:
        print(f"✗ 读取失败：{e}")
        return 1

    applied = skipped = 0
    for table, fname, pk in TABLES:
        path = os.path.join(SRC, fname)
        if not os.path.exists(path):
            print(f"  ⚠ 缺少 {fname}，跳过 {table}")
            continue
        rows = json.load(open(path, encoding="utf-8"))
        cols = [c[1] for c in db.execute(f"PRAGMA table_info({table})")]

        for row in rows:
            payload = {k: v for k, v in row.items() if k in cols}
            if pk not in payload:
                continue

            # 占位符值 → 保留库中原值
            new_vals, has_ph = {}, False
            for c in cols:
                if c not in payload:
                    continue
                v = payload[c]
                if isinstance(v, str) and PLACEHOLDER in v:
                    has_ph = True
                    continue
                new_vals[c] = v
            if has_ph:
                skipped += 1
            if not new_vals:
                continue

            where = f"{pk} = ?"
            args = [new_vals[pk]] if pk in new_vals else [payload[pk]]
            sets = ", ".join(f"{c} = ?" for c in new_vals if c != pk)
            if sets:
                sql = f"update {table} set {sets} where {where}"
                db.execute(sql, [*[v for c, v in new_vals.items() if c != pk], *args])
                applied += 1

        print(f"  ✓ {table:16} 处理 {len(rows):>3} 行")
        if DRY:
            db.rollback()
            print("    (dry-run，已回滚)")
            return 0

    if not DRY:
        db.commit()
    print(f"\n更新 {applied} 行，因占位符跳过 {skipped} 项")
    print("提示：部分 app_metadata 是 codeg 运行时自动写入的，重启后可能变化")
    return 0


if __name__ == "__main__":
    sys.exit(main())
