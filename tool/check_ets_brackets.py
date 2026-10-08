#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""校验鸿蒙端 ArkTS 文件的括号配对（跳过注释与字符串）。

本机没有 DevEco/ArkTS 编译器，改动大文件后先用它兜底，
能抓出「少一个大括号」「多一个圆括号」这类必然编译失败的错。
（不替代真正的编译，语义错误它查不出来。）

用法：
  python tool/check_ets_brackets.py                       # 全量
  python tool/check_ets_brackets.py <file1> <file2> ...   # 指定文件
  python tool/check_ets_brackets.py --changed             # 只查 git 有改动的 .ets
"""

import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ETS_ROOT = os.path.join(ROOT, 'harmony_client', 'entry', 'src', 'main', 'ets')

BACKSLASH = chr(92)
PAIRS = {'(': ')', '[': ']', '{': '}'}
CLOSERS = {v: k for k, v in PAIRS.items()}


def strip_comments_and_strings(src: str) -> str:
    out = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if c == '/' and i + 1 < n and src[i + 1] == '*':
            j = src.find('*/', i + 2)
            i = n if j < 0 else j + 2
            continue
        if c in ('"', "'", '`'):
            quote = c
            i += 1
            while i < n:
                if src[i] == BACKSLASH:
                    i += 2
                    continue
                if src[i] == quote:
                    i += 1
                    break
                i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def check(path: str):
    with open(path, encoding='utf-8') as f:
        src = f.read()
    s = strip_comments_and_strings(src)
    stack = []
    for idx, ch in enumerate(s):
        if ch in PAIRS:
            stack.append(ch)
        elif ch in CLOSERS:
            if not stack or stack[-1] != CLOSERS[ch]:
                line = s.count('\n', 0, idx) + 1
                return f'第 {line} 行附近不匹配：遇到 {ch}，栈顶 {stack[-1] if stack else "空"}'
            stack.pop()
    if stack:
        return f'结尾未闭合：{stack[:8]}'
    return ''


def iter_files(args):
    paths = [a for a in args if not a.startswith('--')]
    if paths:
        for p in paths:
            ap = p if os.path.isabs(p) else os.path.join(ROOT, p)
            if os.path.isfile(ap):
                yield ap
        return
    if '--changed' in args:
        try:
            out = subprocess.run(['git', 'status', '--porcelain'], cwd=ROOT,
                                 capture_output=True, text=True, check=True).stdout
            for line in out.splitlines():
                p = line[3:].strip().strip('"')
                if p.endswith('.ets'):
                    yield os.path.join(ROOT, p.replace('/', os.sep))
            return
        except Exception:  # noqa: BLE001
            pass
    for dirpath, _dirs, files in os.walk(ETS_ROOT):
        for f in files:
            if f.endswith('.ets'):
                yield os.path.join(dirpath, f)


def main():
    total = 0
    bad = []
    for fp in iter_files(sys.argv[1:]):
        total += 1
        msg = check(fp)
        if msg:
            bad.append((os.path.relpath(fp, ROOT).replace(os.sep, '/'), msg))
    print(f'检查 {total} 个 .ets 文件，括号异常 {len(bad)} 个')
    for fp, msg in bad:
        print(f'  x {fp}: {msg}')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
