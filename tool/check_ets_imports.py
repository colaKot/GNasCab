#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""校验鸿蒙端 ArkTS 文件的相对 import/export 路径是否真实存在。

背景：
  ArkTS 的 `from '../models/VideoModels'` 在编译期解析，写错一级目录会直接编译失败；
  本机没有 DevEco/ArkTS 编译器，只能靠脚本做静态体检。

规则：
  - 只检查以 '.' 开头的相对路径（@kit.* / @ohos.* 等系统包跳过）
  - 依次尝试 <target>.ets / <target>.ts / <target>/index.ets

用法：
  python tool/check_ets_imports.py                 # 检查整个 harmony_client/ets
  python tool/check_ets_imports.py --changed       # 只检查 git 有改动的 .ets 文件
"""

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ETS_ROOT = os.path.join(ROOT, 'harmony_client', 'entry', 'src', 'main', 'ets')

IMPORT_RE = re.compile(r"""^\s*(?:import|export)\s[\s\S]*?from\s+['"]([^'"]+)['"]""", re.M)
SIDE_EFFECT_RE = re.compile(r"""^\s*import\s+['"]([^'"]+)['"]""", re.M)


def resolve(base_dir: str, spec: str) -> str:
    target = os.path.normpath(os.path.join(base_dir, spec))
    candidates = [target + '.ets', target + '.ts', target + '.d.ts',
                  os.path.join(target, 'index.ets'), os.path.join(target, 'index.ts')]
    for c in candidates:
        if os.path.isfile(c):
            return c
    return ''


def iter_ets(paths=None):
    if paths:
        for p in paths:
            if p.endswith('.ets') and os.path.isfile(p):
                yield p
        return
    for dirpath, _dirs, files in os.walk(ETS_ROOT):
        for f in files:
            if f.endswith('.ets'):
                yield os.path.join(dirpath, f)


def changed_files():
    try:
        out = subprocess.run(['git', 'status', '--porcelain'], cwd=ROOT,
                             capture_output=True, text=True, check=True).stdout
    except Exception:  # noqa: BLE001
        return None
    files = []
    for line in out.splitlines():
        p = line[3:].strip().strip('"')
        if p.endswith('.ets'):
            files.append(os.path.join(ROOT, p.replace('/', os.sep)))
    return files


def main():
    only_changed = '--changed' in sys.argv
    paths = changed_files() if only_changed else None
    if only_changed and paths is None:
        print('无法读取 git 状态，改为全量检查')
        paths = None

    total = 0
    bad = []
    for fp in iter_ets(paths):
        with open(fp, encoding='utf-8') as f:
            text = f.read()
        specs = set(IMPORT_RE.findall(text)) | set(SIDE_EFFECT_RE.findall(text))
        for spec in specs:
            if not spec.startswith('.'):
                continue
            total += 1
            if not resolve(os.path.dirname(fp), spec):
                bad.append((os.path.relpath(fp, ROOT).replace(os.sep, '/'), spec))

    print(f'扫描 {total} 处相对 import，无法解析 {len(bad)} 处')
    for fp, spec in bad:
        print(f'  x {fp}  ->  {spec}')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
