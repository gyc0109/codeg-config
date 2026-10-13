#!/usr/bin/env python3
"""把 skills 目录布局归一化成 codeg 的约定。

背景 —— codeg 和 skills CLI 的「中央仓库」约定是**相反**的：

  codeg 约定（原有 36 个 skill 都这样）：
      真内容在 ~/.codeg/skills/<name>
      ~/.agents/skills/<name>       -> 符号链接 -> ~/.codeg/skills/<name>
      ~/.<agent>/skills/<name>      -> 符号链接 -> ~/.codeg/skills/<name>

  skills CLI 约定（它装出来的）：
      真内容在 ~/.agents/skills/<name>
      ~/.codeg/skills/<name>        -> 符号链接 -> ~/.agents/skills/<name>

两者混用虽然文件都够得着，但 codeg 的 .manifest.json 记录、UI 的
experts/custom/science/officecli 四套子系统都按「.codeg/skills 是真内容」
来工作，所以统一到 codeg 约定。

skills CLI 每装一次都会按自己的约定写，所以**每次用它装完都要跑一遍本脚本**。

用法: python3 normalize-skills-layout.py [skill名...]    # 不给参数则自动找出所有反向链接
"""
import os
import shutil
import sys

H = os.path.expanduser('~')
CENTRAL = f'{H}/.codeg/skills'
STORE = f'{H}/.agents/skills'
TARGETS = ['.claude/skills', '.pi/agent/skills', '.codex/skills', '.config/opencode/skills',
           '.hermes/skills', '.kimi-code/skills', '.openclaw/skills', '.agents/skills',
           '.codebuddy/skills', '.dsh/skills']


def needs_fix(name):
    c = f'{CENTRAL}/{name}'
    return os.path.islink(c) and os.path.realpath(c).startswith(os.path.realpath(STORE))


names = sys.argv[1:] or sorted(
    e for e in os.listdir(CENTRAL) if not e.startswith('.') and needs_fix(e))

if not names:
    print('  = 无需归一化')
    sys.exit(0)

for s in names:
    c, a = f'{CENTRAL}/{s}', f'{STORE}/{s}'

    # 1) 真内容搬回 ~/.codeg/skills/
    if os.path.islink(c):
        real = os.path.realpath(c)
        if os.path.isdir(real) and not os.path.islink(real):
            tmp = c + '.swap'
            shutil.move(real, tmp)
            os.unlink(c)
            shutil.move(tmp, c)
            print(f'  ✓ {s}: 真内容搬回 ~/.codeg/skills/')

    # 2) ~/.agents/skills 改成指向 ~/.codeg/skills
    if os.path.islink(a):
        if os.path.realpath(a) != os.path.realpath(c):
            os.unlink(a)
            os.symlink(os.path.relpath(c, STORE), a)
    elif os.path.isdir(a):
        shutil.rmtree(a)
        os.symlink(os.path.relpath(c, STORE), a)

    # 3) 所有 agent 目录链到 ~/.codeg/skills
    for t in TARGETS:
        d = os.path.join(H, t)
        os.makedirs(d, exist_ok=True)
        p = os.path.join(d, s)
        if os.path.islink(p):
            if os.path.realpath(p) == os.path.realpath(c):
                continue
            os.unlink(p)
        elif os.path.isdir(p):
            shutil.rmtree(p)
        os.symlink(os.path.relpath(c, d), p)
    print(f'  ✓ {s}: 已链到 {len(TARGETS)} 个 agent 目录')
