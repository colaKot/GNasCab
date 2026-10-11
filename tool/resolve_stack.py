# -*- coding: utf-8 -*-
"""把浏览器控制台整段栈（`xxx @ main.dart.js:12345`）还原成 Dart 文件/行号。

用法：
    python tool/resolve_stack.py --map <map路径> < stack.txt
    python tool/resolve_stack.py --map <map路径> 96794 277386 292049
    python tool/resolve_stack.py --map <map路径> --line 96794 277386

⚠️ 前提：**map 必须和浏览器里跑的那份 main.dart.js 是同一次构建**。
   `flutter build web` 加不加 `--source-maps` 会改变 dart2js 的 mangle 顺序，
   行号会整体错位（实测 394915 vs 394929 行），拿新 map 查旧产物必然查错文件。

关于列号：
   - 带列号（`main.dart.js:123:45`）⇒ 精确取该列所在的映射段。
   - 只有行号（`main.dart.js:123`）⇒ 列出该行的**全部**候选来源。
     dart2js 把大量 Dart 源码压成极少数超长行，一行 JS 常混着多个 Dart 文件，
     所以无列号时不能只信第一个候选；带 ★ 的是 app 自己的代码，通常就是真凶。
"""
import argparse
import json
import os
import re
import sys
from collections import defaultdict, OrderedDict

DEFAULT_MAP = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    'electron_server', 'web', 'main', 'main.dart.js.map',
)

B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
B64MAP = {c: i for i, c in enumerate(B64)}

FRAME_RE = re.compile(r'main\.dart\.js:(\d+)(?::(\d+))?')


def decode_vlq(seg):
    values, shift, acc = [], 0, 0
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
            shift, acc = 0, 0
    while len(values) < 4:
        values.append(0)
    return values[:4]


def load_map(map_path):
    with open(map_path, 'r', encoding='utf-8') as f:
        m = json.load(f)
    sources = m.get('sources', [])
    index = {}
    for line_no, line in enumerate(m['mappings'].split(';')):
        if not line:
            continue
        segs = []
        gen_col = src_i = prev_line = prev_col = 0
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


def norm(src):
    return src.replace('webpack:///', '').replace('org-dartlang-sdk:///', '')


def is_app(src):
    """真正的「我们自己的代码」。flutter / dart-sdk / pub 第三方包都不算。"""
    s = norm(src)
    if '/flutter/packages/flutter/' in s or '/dart-sdk/' in s:
        return False
    if s.startswith('dart:') or s.startswith('dart-sdk/'):
        return False
    if is_thirdparty(src):
        return False
    return True


def is_thirdparty(src):
    s = norm(src)
    low = s.lower()
    return ('/pub/cache/' in low or '/.pub-cache/' in low
            or '/hosted/pub.dev/' in low or '/hosted/pub.dartlang.org/' in low)


def report(map_path, frames, show_all):
    if not os.path.exists(map_path):
        sys.exit('source map 不存在: %s' % map_path)
    sources, index = load_map(map_path)
    print('map: %s' % map_path)
    print('=' * 72)

    app_hits = OrderedDict()
    for gen_line, gen_col in frames:
        gl = gen_line - 1
        segs = index.get(gl)
        head = 'main.dart.js:%d' % gen_line
        if gen_col:
            head += ':%d' % gen_col
        if not segs:
            print('%-22s (无映射 —— 纯 JS 胶水)' % head)
            continue

        picked = None
        if gen_col:
            want = gen_col - 1
            for gc, si, sl, sc in segs:
                if gc <= want:
                    picked = (gc, si, sl, sc)
                else:
                    break

        if picked:
            gc, si, sl, sc = picked
            src = norm(sources[si]) if 0 <= si < len(sources) else '?'
            tag = '★APP' if is_app(src) else ('pkg ' if is_thirdparty(src) else 'fw  ')
            print('%-22s %s  %s:%d:%d' % (head, tag, src, sl + 1, sc + 1))
            if is_app(src):
                app_hits.setdefault((src, sl + 1), 0)
                app_hits[(src, sl + 1)] += 1
        else:
            agg = defaultdict(int)
            for gc, si, sl, sc in segs:
                if 0 <= si < len(sources):
                    agg[(norm(sources[si]), sl + 1)] += 1
            apps = [(k, v) for k, v in agg.items() if is_app(k[0])]
            print('%s  (无列号，该行 %d 个候选)' % (head, len(agg)))
            for (src, sl), c in sorted(apps, key=lambda x: -x[1])[:show_all]:
                print('        ★APP %s:%d  (%d 段)' % (src, sl, c))
                app_hits.setdefault((src, sl), 0)
                app_hits[(src, sl)] += c

    print()
    print('---- app 代码命中汇总（按出现次数）----')
    if not app_hits:
        print('  (本次栈里没有 app 源码帧 —— 说明异常来自框架布局/约束)')
    for (src, sl), c in sorted(app_hits.items(), key=lambda x: -x[1])[:20]:
        print('  %5d  %s:%d' % (c, src, sl))


def parse_frames(text):
    frames = []
    for m in FRAME_RE.finditer(text):
        line = int(m.group(1))
        col = int(m.group(2)) if m.group(2) else None
        frames.append((line, col))
    seen = set()
    out = []
    for f in frames:
        if f not in seen:
            seen.add(f)
            out.append(f)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--map', default=DEFAULT_MAP)
    ap.add_argument('--line', action='store_true', help='参数只当行号处理（无列号）')
    ap.add_argument('--all', type=int, default=6, help='无列号时每行最多列几个候选')
    ap.add_argument('rest', nargs='*')
    args = ap.parse_args()

    if args.rest:
        frames = []
        for a in args.rest:
            if ':' in a:
                l, c = a.split(':', 1)
                frames.append((int(l), int(c)))
            else:
                frames.append((int(a), None if args.line else 1))
    else:
        data = sys.stdin.read()
        if not data.strip():
            sys.exit('没有输入：把控制台栈粘到标准输入，或用参数传行号')
        frames = parse_frames(data)

    report(args.map, frames, args.all)


if __name__ == '__main__':
    main()
