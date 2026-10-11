# -*- coding: utf-8 -*-
"""把浏览器控制台里的 `xxx @ main.dart.js:LINE:COL` 栈帧还原成 Dart 文件/行号。

用法：
    python tool/resolve_minified_frames.py 96794 277386 292049 ...
    python tool/resolve_minified_frames.py --stdin     # 从标准输入逐行读帧

原理：main.dart.js.map 里的 mappings 用 VLQ 编码，段格式是
    [生成的列增量, 源文件索引增量, 源行增量, 源列增量]
按 generated line/col 查最近的段即可拿到 Dart 位置。

⚠️ dart2js release 会把符号名 mangle 掉，所以只能定位到**文件+行**，
   看不到函数名；但这已经足够定位是哪个 widget /哪行出的问题。
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MAP = os.path.join(ROOT, 'flutter_client', 'build', 'web', 'main.dart.js.map')

B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
B64MAP = {c: i for i, c in enumerate(B64)}


def decode_vlq(seg):
    """解一段 VLQ，返回 [genCol, srcIdx, srcLine, srcCol]。"""
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


def load_index():
    with open(MAP, 'r', encoding='utf-8') as f:
        return json.load(f)


class Resolver:
    def __init__(self, map_path=MAP):
        with open(map_path, 'r', encoding='utf-8') as f:
            m = json.load(f)
        self.sources = m.get('sources', [])
        self.sources_content = m.get('sourcesContent')
        self.groups = []          # 每项: (genLine, [(genCol, srcIdx, srcLine, srcCol), ...])
        prev_src = 0
        for line_no, line in enumerate(m['mappings'].split(';')):
            segs = []
            gen_col = 0
            src_i = prev_src
            prev_line = 0
            prev_col = 0
            for seg in line.split(','):
                if not seg:
                    continue
                v = decode_vlq(seg)
                gen_col += v[0]
                if len(v) >= 4 and v[1] != 0 or (len(v) == 4 and prev_src >= 0 and v[1]):
                    pass
                src_i += v[1]
                prev_line += v[2]
                prev_col += v[3]
                segs.append((gen_col, src_i, prev_line, prev_col))
            prev_src = src_i
            if segs:
                self.groups.append((line_no, segs))

    def resolve(self, gen_line, gen_col):
        # 浏览器报的行是 1-based
        gl = gen_line - 1
        best = None
        lo, hi = 0, len(self.groups) - 1
        idx = None
        while lo <= hi:
            mid = (lo + hi) // 2
            if self.groups[mid][0] <= gl:
                idx = mid
                lo = mid + 1
            else:
                hi = mid - 1
        if idx is None:
            return None
        cand = None
        for gc, si, sl, sc in self.groups[idx][1]:
            if gc <= gen_col - 1:
                cand = (gc, si, sl, sc)
            else:
                break
        if cand is None and self.groups[idx][1]:
            cand = self.groups[idx][1][0]
        if cand is None:
            return None
        _, si, sl, sc = cand
        if not (0 <= si < len(self.sources)):
            return None
        src = self.sources[si].replace('webpack:///', '')
        return src, sl + 1, sc + 1


def main():
    args = sys.argv[1:]
    if not args or args[0] == '--stdin':
        frames = []
        for line in sys.stdin:
            line = line.strip()
            if not line or '@' not in line:
                continue
            loc = line.split('@')[-1].strip()
            parts = loc.replace('main.dart.js', '').strip().split(':')
            try:
                frames.append((int(parts[0]), int(parts[1]) if len(parts) > 1 else 1))
            except (ValueError, IndexError):
                continue
    else:
        frames = [(int(a), 1) for a in args]

    if not os.path.exists(MAP):
        sys.exit('source map 不存在: %s\n先跑 tool\\build_web_sourcemap.bat' % MAP)

    r = Resolver()
    seen = {}
    for line, col in frames:
        res = r.resolve(line, col)
        key = res[0] if res else None
        seen[key] = seen.get(key, 0) + 1
        if res:
            src, sl, sc = res
            print('main.dart.js:%-7d => %s:%d:%d' % (line, src, sl, sc))
        else:
            print('main.dart.js:%-7d => (无映射)' % line)

    print('\n---- 命中文件汇总 ----')
    for k, v in sorted(seen.items(), key=lambda x: -x[1]):
        if k:
            print('%5d  %s' % (v, k))


if __name__ == '__main__':
    main()