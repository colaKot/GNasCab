# -*- coding: utf-8 -*-
"""列出 main.dart.js 某一行的**全部** Dart 映射候选。

为什么不用列号：浏览器控制台复制出来的栈帧常常只有 `main.dart.js:277386`，
没有列号（列号会出现在 `func@file:line:col` 里，但 Flutter release 的
mangle 让 col 常常被省略）。而 dart2js 会把大量 Dart 源码压成极少数超长行，
**同一行 JS 可能对应好几个不同的 Dart 文件**。所以按 col=1 反查很容易查错文件。

正确做法：把该JS 行上的所有映射段全列出来，看候选里有几个 app 文件。
通常真正的 app 文件会明显露出来。

用法：
    python tool/resolve_line_candidates.py 277386 277630 292049 ...
"""
import json
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MAP = os.path.join(ROOT, 'flutter_client', 'build', 'web', 'main.dart.js.map')

B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
B64MAP = {c: i for i, c in enumerate(B64)}


def decode_vlq(seg):
    values = []
    shift = 0
    acc = 0
    for ch in seg:
        d = B64MAP[ch]
        cont = d & 32
        d &= 31
        acc += d << shift
        if cont:
            shift += 5
        else:
            neg = acc & 1
            val = acc >> 1
            values.append(-val if neg else val)
            shift = 0
            acc = 0
    while len(values) < 4:
        values.append(0)
    return values[:4]


def build_line_index(map_path=MAP):
    """返回 {gen_line_0based: [ (genCol, sourceIdx, srcLine, srcCol) ]}"""
    with open(map_path, 'r', encoding='utf-8') as f:
        m = json.load(f)
    sources = m.get('sources', [])
    index = {}
    for line_no, line in enumerate(m['mappings'].split(';')):
        if not line:
            continue
        segs = []
        gen_col = 0
        src_i = 0
        prev_line = 0
        prev_col = 0
        for seg in line.split(','):
            if not seg:
                continue
            v = decode_vlq(seg)
            gen_col += v[0]
            src_i += v[1]
            prev_line += v[2]
            prev_col += v[3]
            segs.append((gen_col, src_i, prev_line, prev_col))
        if segs:
            index[line_no] = segs
    return sources, index


def is_app_source(src):
    s = src.replace('webpack:///', '')
    if '/flutter/packages/flutter/' in s:
        return False
    if s.startswith('org-dartlang-sdk:'):
        return False
    if '/dart-sdk/' in s or s.startswith('dart:'):
        return False
    return True


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    if not os.path.exists(MAP):
        sys.exit('source map 不存在: %s\n先跑 tool\\build_web_sourcemap.bat' % MAP)

    sources, index = build_line_index()
    for a in args:
        try:
            gl = int(a) - 1
        except ValueError:
            continue
        segs = index.get(gl)
        print('=' * 70)
        print('main.dart.js:%s  (%d 个映射段)' % (a, len(segs) if segs else 0))
        if not segs:
            print('  (该行无映射 —— 多半是纯JS 胶水代码)')
            continue
        agg = defaultdict(int)
        for gc, si, sl, sc in segs:
            if not (0 <= si < len(sources)):
                continue
            src = sources[si].replace('webpack:///', '')
            agg[(src, sl + 1)] += 1
        app = [(k, v) for k, v in agg.items() if is_app_source(k[0])]
        fw = [(k, v) for k, v in agg.items() if not is_app_source(k[0])]
        if app:
            print('  ★ APP 源码候选（最可能是真正出问题的位置）:')
            for (src, sl), v in sorted(app, key=lambda x: -x[1])[:12]:
                print('      %-70s :%d  (%d 段)' % (src, sl, v))
        if fw:
            print('  - 框架候选:')
            for (src, sl), v in sorted(fw, key=lambda x: -x[1])[:6]:
                print('      %-70s :%d  (%d 段)' % (src, sl, v))


if __name__ == '__main__':
    main()