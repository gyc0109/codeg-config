#!/usr/bin/env python3
"""给 skills CLI 打 codeg 补丁（幂等）。

skills CLI (npm 包 `skills`) 内置的 agent 名单里没有 codeg，
导致 `skills add -a codeg` 装不进 ~/.codeg/skills/。

npm update skills 会覆盖 cli.mjs，所以本脚本要存下来，升级后重跑。

用法: python3 patch-skills-cli.py [cli.mjs 路径]
"""
import os
import re
import shutil
import subprocess
import sys
import time

CLI = sys.argv[1] if len(sys.argv) > 1 else '/usr/lib/node_modules/skills/dist/cli.mjs'

if not os.path.exists(CLI):
    sys.exit(f'✗ 找不到 {CLI}')

src = open(CLI).read()

# 幂等检查
if re.search(r'displayName:\s*"codeg"', src):
    print(f'  = 已含 codeg 条目，跳过：{CLI}')
    sys.exit(0)

# 找 `const agents = {`
m = re.search(r'^(\s*)const agents = \{\s*$', src, re.M)
if not m:
    sys.exit('✗ 找不到 "const agents = {"，CLI 结构可能变了，请人工检查')

indent = m.group(1)          # 顶层缩进（通常是空）
body = indent + '\t'         # 条目缩进（\t）
inner = body + '\t'          # 字段缩进
deep = inner + '\t'          # 函数体缩进

entry = (
    f'{body}codeg: {{\n'
    f'{inner}name: "codeg",\n'
    f'{inner}displayName: "codeg",\n'
    f'{inner}skillsDir: ".codeg/skills",\n'
    f'{inner}globalSkillsDir: join(home, ".codeg/skills"),\n'
    f'{inner}detectInstalled: async () => {{\n'
    f'{deep}return existsSync(join(home, ".codeg"));\n'
    f'{inner}}}\n'
    f'{body}}},\n'
)

# 备份
bk = CLI + '.bak.' + str(int(time.time()))
shutil.copy2(CLI, bk)
print(f'  备份: {bk}')

# 插入到 `const agents = {` 之后
insert_at = m.end()
src = src[:insert_at] + '\n' + entry.rstrip('\n') + src[insert_at:]
open(CLI, 'w').write(src)
print(f'  ✓ 已插入 codeg 条目')

# 语法检查
r = subprocess.run(['node', '--check', CLI], capture_output=True, text=True)
if r.returncode != 0:
    shutil.copy2(bk, CLI)
    sys.exit(f'✗ 语法检查失败，已回滚:\n{r.stderr[:400]}')
print(f'  ✓ node --check 通过')
