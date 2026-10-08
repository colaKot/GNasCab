# -*- coding: utf-8 -*-
"""轻量 Dart 语法兜底检查：跳过注释与字符串后校验括号配对。"""
import sys

PAIRS = {')': '(', ']': '[', '}': '{'}
OPEN = set('([{')


def check(path):
    try:
        src = open(path, encoding='utf-8').read()
    except Exception as e:
        return '读取失败: %s' % e

    stack = []
    i = 0
    n = len(src)
    line = 1
    while i < n:
        c = src[i]
        if c == '\n':
            line += 1
            i += 1
            continue
        # 行注释
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            while i < n and src[i] != '\n':
                i += 1
            continue
        # 块注释
        if c == '/' and i + 1 < n and src[i + 1] == '*':
            i += 2
            while i + 1 < n and not (src[i] == '*' and src[i + 1] == '/'):
                if src[i] == '\n':
                    line += 1
                i += 1
            i += 2
            continue
        # 字符串（含三引号）
        if c in ("'", '"'):
            q = c
            triple = src.startswith(q * 3, i)
            delim = q * 3 if triple else q
            i += len(delim)
            while i < n:
                if src[i] == '\\':
                    i += 2
                    continue
                if src[i] == '\n':
                    line += 1
                if src.startswith(delim, i):
                    i += len(delim)
                    break
                i += 1
            continue
        if c in OPEN:
            stack.append((c, line))
            i += 1
            continue
        if c in PAIRS:
            if not stack:
                return '第 %d 行多出 %s' % (line, c)
            top, tl = stack.pop()
            if top != PAIRS[c]:
                return '第 %d 行 %s 与第 %d 行 %s 不匹配' % (line, c, tl, top)
            i += 1
            continue
        i += 1

    if stack:
        top, tl = stack[-1]
        return '第 %d 行 %s 未闭合' % (tl, top)
    return None


bad = 0
for p in sys.argv[1:]:
    r = check(p)
    if r:
        bad += 1
        print('FAIL %s : %s' % (p.replace(chr(92), '/'), r))
    else:
        print('OK   %s' % p.replace(chr(92), '/'))
print('---- 失败 %d / 共 %d' % (bad, len(sys.argv[1:])))
