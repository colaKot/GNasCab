#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 Flutter 语言包里的指定键同步到鸿蒙端 locales JSON。

背景：
  Flutter 语言包 = lib/core/languages/<code>.dart，扁平 map，值用单引号。
  鸿蒙语言包   = resources/rawfile/locales/<code>.json，扁平 JSON。
  两端 key 必须一一对应，新增文案时容易漏掉鸿蒙端。

本脚本做两件事：
  1. 从 Flutter dart 提取指定前缀的键（默认 video_library / video_source_select_library）
  2. 按字母序插入到鸿蒙 JSON 中（**行级插入**，不重写整个文件 → diff 干净）

占位符风格差异：
  Flutter 用 {name}，鸿蒙 L10n.t() 用 @name → 自动转换。

用法：
  python tool/sync_harmony_locale_keys.py                 # 用内置默认前缀
  python tool/sync_harmony_locale_keys.py video_library   # 指定前缀
  python tool/sync_harmony_locale_keys.py --dry-run       # 只报告不写入
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FLUTTER_DIR = os.path.join(ROOT, 'flutter_client', 'lib', 'core', 'languages')
HARMONY_DIR = os.path.join(
    ROOT, 'harmony_client', 'entry', 'src', 'main', 'resources', 'rawfile', 'locales')

# Flutter 语言文件 → 鸿蒙 JSON 文件
LOCALES = [
    ('ar_ar', 'ar-ar.json'),
    ('de_de', 'de-de.json'),
    ('en_us', 'en-us.json'),
    ('es_es', 'es-es.json'),
    ('fr_fr', 'fr-fr.json'),
    ('id_id', 'id-id.json'),
    ('ja_jp', 'ja-jp.json'),
    ('ko_kr', 'ko-kr.json'),
    ('pt_br', 'pt-br.json'),
    ('ru_ru', 'ru-ru.json'),
    ('th_th', 'th-th.json'),
    ('vi_vn', 'vi-vn.json'),
    ('zh_cn', 'zh-cn.json'),
]

DEFAULT_PREFIXES = ['video_library', 'video_source_select_library']

# 单行条目：  'key': 'value',
# 值允许 \' \\ 转义；多行条目（值折行）本脚本不处理，会打印告警。
ENTRY_RE = re.compile(r"^\s*'((?:[^'\\]|\\.)*)'\s*:\s*'((?:[^'\\]|\\.)*)'\s*,\s*$")


def dart_unescape(s: str) -> str:
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            nxt = s[i + 1]
            if nxt == 'n':
                out.append('\n')
            elif nxt == 't':
                out.append('\t')
            elif nxt == 'r':
                out.append('\r')
            else:
                out.append(nxt)
            i += 2
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def read_flutter(path: str, prefixes=None, verbose: bool = False) -> dict:
    """返回 {key: value}；多行条目跳过（仅当键命中 prefixes 时告警）。"""
    entries = {}
    with open(path, encoding='utf-8') as f:
        for lineno, line in enumerate(f, 1):
            s = line.rstrip('\n').rstrip('\r')
            if not s.strip() or s.strip().startswith('//'):
                continue
            m = ENTRY_RE.match(s)
            if m:
                key = dart_unescape(m.group(1))
                val = dart_unescape(m.group(2))
                entries[key] = val
                continue
            # 疑似被折行的条目：只有命中目标前缀才值得关注
            km = re.match(r"^\s*'((?:[^'\\]|\\.)*)'\s*:", s)
            if km and prefixes and any(km.group(1).startswith(p) for p in prefixes):
                print(f'  ! {os.path.basename(path)}:{lineno} 目标键为多行条目，已跳过: {s.strip()[:70]}')
            elif km and verbose:
                print(f'  ~ {os.path.basename(path)}:{lineno} 多行条目(非目标)已跳过')
    return entries


BRACE_RE = re.compile(r'\{([A-Za-z0-9_]+)\}')


def to_json_literal(val: str) -> str:
    """dart 值 → 鸿蒙 JSON 值字面量（{x} → @x，并做 JSON 转义）。"""
    converted = BRACE_RE.sub(lambda m: '@' + m.group(1), val)
    return json.dumps(converted, ensure_ascii=False)


def json_key_of(line: str):
    m = re.match(r'^\s*"((?:[^"\\]|\\.)*)"\s*:', line)
    return m.group(1) if m else None


def insert_into_json(path: str, new_entries: dict, dry_run: bool) -> tuple:
    """行级插入。返回 (added, updated, unchanged)。"""
    with open(path, 'rb') as f:
        raw = f.read()
    text = raw.decode('utf-8')
    lines = text.split('\r\n')
    has_trailing = lines and lines[-1] == ''
    if has_trailing:
        lines = lines[:-1]

    # 记录现有键的行号，以及"去掉末尾逗号的最后一行"位置
    existing = {}
    for i, ln in enumerate(lines):
        k = json_key_of(ln)
        if k is not None:
            existing[k] = i

    # 小写块起始位置（大写键块之后），只在其中做字母序插入
    low_start = 0
    while low_start < len(lines) and (json_key_of(lines[low_start]) or 'a')[0].isupper():
        low_start += 1

    added = updated = unchanged = 0
    for key in sorted(new_entries.keys(), key=lambda s: s.lower()):
        literal = f'  "{key}": {to_json_literal(new_entries[key])}'
        if key in existing:
            idx = existing[key]
            cur = json_key_of(lines[idx])
            if lines[idx].rstrip().rstrip(',') == literal:
                unchanged += 1
                continue
            # 替换：保留原行是否带逗号
            comma = ',' if lines[idx].rstrip().endswith(',') else ''
            lines[idx] = literal + comma
            updated += 1
            continue

        # 找插入点：小写块内第一个 key 大于目标的行
        pos = len(lines)
        for i in range(low_start, len(lines)):
            k = json_key_of(lines[i])
            if k is None:
                continue
            if k.lower() > key.lower():
                pos = i
                break
        lines.insert(pos, literal + ',')
        # 行号后移
        for k2 in list(existing.keys()):
            if existing[k2] >= pos:
                existing[k2] += 1
        existing[key] = pos
        added += 1

    if not dry_run and (added or updated):
        # 最后一条有效条目不能有尾逗号
        body = [ln for ln in lines if ln.strip() != '']
        for i in range(len(body) - 1, -1, -1):
            if json_key_of(body[i]) is not None:
                body[i] = body[i].rstrip().rstrip(',')
                break
        out = '\r\n'.join(body) + '\r\n'
        with open(path, 'wb') as f:
            f.write(out.encode('utf-8'))

    return added, updated, unchanged


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    dry_run = '--dry-run' in sys.argv
    prefixes = args if args else DEFAULT_PREFIXES

    print(f'前缀: {prefixes}    模式: {"DRY-RUN" if dry_run else "写入"}')
    total_added = total_updated = 0
    for dart_code, json_name in LOCALES:
        dart_path = os.path.join(FLUTTER_DIR, f'{dart_code}.dart')
        json_path = os.path.join(HARMONY_DIR, json_name)
        if not os.path.exists(dart_path) or not os.path.exists(json_path):
            print(f'  x 缺少文件: {dart_path} / {json_path}')
            continue
        entries = read_flutter(dart_path, prefixes)
        picked = {k: v for k, v in entries.items()
                  if any(k.startswith(p) for p in prefixes)}
        if not picked:
            print(f'  - {dart_code}: 未匹配到任何键')
            continue
        a, u, s = insert_into_json(json_path, picked, dry_run)
        total_added += a
        total_updated += u
        print(f'  {dart_code:6s} -> {json_name:12s} 新增 {a:2d}  更新 {u:2d}  已是 {s:2d}   (源 {len(picked)})')

    print(f'合计: 新增 {total_added}，更新 {total_updated}')

    if dry_run:
        print('DRY-RUN：未写入，跳过落盘校验')
        return

    # 校验：每个 JSON 仍可解析，且键集合与 Flutter 一致
    bad = []
    for dart_code, json_name in LOCALES:
        json_path = os.path.join(HARMONY_DIR, json_name)
        try:
            with open(json_path, encoding='utf-8') as f:
                data = json.load(f)
        except Exception as e:  # noqa: BLE001
            bad.append(f'{json_name} JSON 解析失败: {e}')
            continue
        dart_path = os.path.join(FLUTTER_DIR, f'{dart_code}.dart')
        entries = read_flutter(dart_path, prefixes)
        for k in entries:
            if any(k.startswith(p) for p in prefixes) and k not in data:
                bad.append(f'{json_name} 缺键 {k}')
    if bad:
        print('校验失败:')
        for b in bad:
            print('  x', b)
        sys.exit(1)
    print('校验通过: 全部 JSON 可解析，目标键均已落盘')


if __name__ == '__main__':
    main()
