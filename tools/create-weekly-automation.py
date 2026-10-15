#!/usr/bin/env python3
"""在 codeg 里创建「每周模型巡检」定时任务。

用 codeg 原生的 automation API（不是系统 cron），这样任务会出现在 codeg UI 的
自动化面板里，执行记录、失败计数都由 codeg 管。

用法: python3 create-weekly-automation.py [--cron "0 4 * * 2,4,6"] [--folder-id 22] [--agent pi]
"""
import argparse
import json
import os
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))


def token():
    for line in open('/etc/codeg.env'):
        if line.startswith('CODEG_TOKEN='):
            return line.split('=', 1)[1].strip()
    raise SystemExit('✗ /etc/codeg.env 里没有 CODEG_TOKEN')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--cron', default='0 4 * * 2,4,6', help='默认周二+周四+周六 04:00')
    ap.add_argument('--timezone', default='Asia/Shanghai')
    ap.add_argument('--agent', default='pi')
    ap.add_argument('--folder-id', type=int, default=22, help='codeg 里的 folder id')
    ap.add_argument('--isolation', default='shared_in_root',
                    choices=['shared_in_root', 'worktree_per_run'])
    ap.add_argument('--prompt-file',
                    default=os.path.join(HERE, 'weekly-refresh-prompt.md'))
    ap.add_argument('--api', default='http://127.0.0.1:3080/api')
    args = ap.parse_args()

    prompt = open(args.prompt_file).read()
    draft = {
        'name': '每周模型巡检',
        'enabled': True,
        'trigger_kind': 'schedule',
        'cron': args.cron,
        'timezone': args.timezone,
        'agent_type': args.agent,
        'isolation': args.isolation,
        'is_remote_branch': False,
        'root_folder_id': args.folder_id,
        'branch': None,
        'config': {
            'action': 'launch_session',
            'prompt_blocks': [{'type': 'text', 'text': prompt}],
            'display_text': '每周模型巡检',
        },
    }

    req = urllib.request.Request(
        f'{args.api}/automation_create',
        data=json.dumps({'draft': draft}).encode(),
        headers={'Content-Type': 'application/json',
                 'Authorization': 'Bearer ' + token()})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            res = json.loads(r.read())
    except Exception as e:
        body = e.read().decode()[:400] if hasattr(e, 'read') else str(e)
        raise SystemExit(f'✗ 创建失败: {body}')

    print(f"✓ 已创建 id={res['id']}")
    print(f"  name     : {res['name']}")
    print(f"  cron     : {res['cron']}  ({res['timezone']})")
    print(f"  next_run : {res['next_run_at']}")
    print(f"  agent    : {res['agent_type']}  folder=#{res['root_folder_id']}  isolation={res['isolation']}")


if __name__ == '__main__':
    main()
