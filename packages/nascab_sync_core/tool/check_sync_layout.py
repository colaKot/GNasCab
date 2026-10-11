#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""检查「同步代码共享」这套结构有没有被改坏。

跑法（在仓库根目录）：
    python packages/nascab_sync_core/tool/check_sync_layout.py

用途：改完共享包或任一端宿主实现后跑一次，能在没有 IDE 的情况下抓出
      断链 import、漏导入共享包、宿主接口没实现全、括号写崩这类问题。

注意：这不能替代 `flutter analyze`，它只做源码级结构校验。
"""
from __future__ import annotations

import io
import os
import re
import sys

TOOL_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(TOOL_DIR)))

CORE = os.path.join(ROOT, 'packages', 'nascab_sync_core', 'lib')
CHECK_DIRS = [
    os.path.join(ROOT, 'packages', 'nascab_sync_core', 'lib'),
    os.path.join(ROOT, 'flutter_client', 'lib', 'modules', 'sync'),
    os.path.join(ROOT, 'flutter_client', 'lib', 'main.dart'),
    os.path.join(ROOT, 'sync_client', 'lib'),
]

HOST_IMPLS = [
    ('主客户端 FlutterSyncHost',
     os.path.join(ROOT, 'flutter_client', 'lib', 'modules', 'sync',
                  'service', 'sync_host_impl.dart')),
    ('独立端 DesktopSyncHost',
     os.path.join(ROOT, 'sync_client', 'lib', 'sync', 'desktop_host_impl.dart')),
]

HOST_METHODS = {'resolveAccessToken', 'message', 'uploadFile', 'sendDownload',
                'plan', 'deleteRemote', 'report'}

SHARED_API = {
    'SyncTask', 'SyncFilterConfig', 'SyncConfig', 'LocalFileEntry', 'SyncPlan',
    'SyncEngine', 'SyncPhase', 'SyncProgress', 'SyncRunResult',
    'SyncLocalScanner', 'SyncLocalStore', 'SyncScheduler', 'SyncScanResult',
    'SyncHost', 'SyncHostHolder', 'SyncApiResult', 'SyncDownloadStream',
    'SyncEndpoint', 'SyncProtocol',
}

# 共享包里不该出现的客户端专有符号
FOREIGN = ['ApiController', 'UploadCore', 'BaseApiService', 'SyncHttp.',
           'SessionController', 'SyncUploader', 'createHttpClient',
           'createSyncHttpClient', 'package:WaterNasOS']

SHARED_EXPORTS = [
    'sync_engine.dart', 'sync_host.dart', 'sync_local_scanner.dart',
    'sync_local_store.dart', 'sync_models.dart', 'sync_protocol.dart',
    'sync_scheduler.dart',
]

errors: list[str] = []


def read(path: str) -> str:
    with io.open(path, 'r', encoding='utf-8') as f:
        return f.read()


def all_dart(entry: str) -> list[str]:
    if entry.endswith('.dart'):
        return [entry] if os.path.exists(entry) else []
    out = []
    for dp, _, fns in os.walk(entry):
        for fn in fns:
            if fn.endswith('.dart'):
                out.append(os.path.join(dp, fn))
    return sorted(out)


def strip_code(src: str) -> str:
    """剥离注释与字符串字面量，保留括号结构（含 ${} 插值嵌套）。"""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        raw = False
        if (c in 'rR' and i + 1 < n and src[i + 1] in '\'"'
                and (i == 0 or not (src[i - 1].isalnum() or src[i - 1] == '_'))):
            raw = True
            i += 1
            c = src[i]
        if c in '\'"':
            q = c * 3 if src[i:i + 3] == c * 3 else c
            j = i + len(q)
            while j < n:
                if src[j:j + len(q)] == q:
                    j += len(q)
                    break
                if not raw and src[j] == '\\':
                    j += 2
                    continue
                if not raw and src[j] == '$' and src[j + 1:j + 2] == '{':
                    depth, k = 1, j + 2
                    while k < n and depth:
                        depth += (src[k] == '{') - (src[k] == '}')
                        k += 1
                    j = k
                    continue
                j += 1
            out.append('S')
            i = j
            continue
        if c == '/' and src[i + 1:i + 2] in ('/', '*'):
            if src[i + 1] == '/':
                j = src.find('\n', i)
                i = n if j < 0 else j
            else:
                j = src.find('*/', i + 2)
                i = n if j < 0 else j + 2
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def c_imports():
    bad = 0
    for d in CHECK_DIRS:
        for f in all_dart(d):
            for m in re.finditer(r"^import\s+'([^']+)'", read(f), re.M):
                imp = m.group(1)
                if imp.startswith(('dart:', 'package:')):
                    continue
                tgt = os.path.normpath(os.path.join(os.path.dirname(f), imp))
                if not os.path.exists(tgt):
                    errors.append('断链 import: %s -> %s'
                                  % (os.path.relpath(f, ROOT), imp))
                    bad += 1
    print('  [1] import 目标        %s' % ('✓ 全部可达' if not bad else '✗ %d 处' % bad))


def c_package_decl():
    decl = {}
    for proj, pub in (('flutter_client', 'flutter_client/pubspec.yaml'),
                      ('sync_client', 'sync_client/pubspec.yaml'),
                      ('nascab_sync_core', 'packages/nascab_sync_core/pubspec.yaml')):
        p = os.path.join(ROOT, pub)
        decl[proj] = set(re.findall(r'^\s{2}([a-z_0-9]+):', read(p), re.M)) if os.path.exists(p) else set()
    bad = 0
    for d in CHECK_DIRS:
        for f in all_dart(d):
            rel = os.path.relpath(f, ROOT).replace('\\', '/')
            proj = ('flutter_client' if rel.startswith('flutter_client')
                    else 'sync_client' if rel.startswith('sync_client')
                    else 'nascab_sync_core')
            for m in re.finditer(r"^import\s+'package:([a-z_0-9]+)/", read(f), re.M):
                pkg = m.group(1)
                if pkg in ('flutter', 'flutter_test', 'flutter_lints'):
                    continue
                if pkg not in decl.get(proj, set()):
                    errors.append('%s 用了未声明依赖 %s（%s）' % (proj, pkg, rel))
                    bad += 1
    print('  [2] 依赖声明          %s' % ('✓ 无遗漏' if not bad else '✗ %d 处' % bad))


def c_shared_import():
    bad = 0
    # 共享包自身不需要 import 自己，只查两个客户端
    for d in (CHECK_DIRS[1], CHECK_DIRS[2], CHECK_DIRS[3]):
        for f in all_dart(d):
            src = read(f)
            if 'package:nascab_sync_core' in src:
                continue
            used = {s for s in SHARED_API if re.search(r'\b%s\b' % s, strip_code(src))}
            if not used:
                continue
            m = re.search(r"part of\s+'([^']+)'", src)
            if m:
                tgt = os.path.normpath(os.path.join(os.path.dirname(f), m.group(1)))
                if os.path.exists(tgt) and 'package:nascab_sync_core' in read(tgt):
                    continue
                errors.append('part 主库未导入共享包: %s' % os.path.relpath(f, ROOT))
                bad += 1
                continue
            errors.append('用了 %s 但未导入共享包: %s'
                          % (','.join(sorted(used)), os.path.relpath(f, ROOT)))
            bad += 1
    print('  [3] 共享包导入        %s' % ('✓ 齐备' if not bad else '✗ %d 处' % bad))


def c_host_implements():
    bad = 0
    for label, path in HOST_IMPLS:
        if not os.path.exists(path):
            errors.append('宿主实现缺失: %s' % path)
            bad += 1
            continue
        src = read(path)
        got = set(re.findall(r'@override\s+(?:[\w<>?,\s.]+?)\b(\w+)\s*\(', src))
        got |= set(re.findall(r'@override\s+(?:String|bool|int)\s+get\s+(\w+)', src))
        miss = HOST_METHODS - got
        if miss:
            errors.append('%s 未实现: %s' % (label, ','.join(sorted(miss))))
            bad += 1
    print('  [4] 宿主接口完整性    %s' % ('✓ 两端完整' if not bad else '✗ %d 处' % bad))


def c_foreign_symbols():
    bad = 0
    for f in all_dart(CORE):
        code = strip_code(read(f))
        for p in FOREIGN:
            if p in code:
                errors.append('共享包残留 %s（%s）' % (p, os.path.relpath(f, ROOT)))
                bad += 1
    print('  [5] 共享包纯度        %s' % ('✓ 无客户端专有符号' if not bad else '✗ %d 处' % bad))


def c_barrel():
    barrel = os.path.join(CORE, 'nascab_sync_core.dart')
    if not os.path.exists(barrel):
        errors.append('缺少 barrel 文件 lib/nascab_sync_core.dart')
        print('  [6] barrel 导出       ✗ 缺失')
        return
    src = read(barrel)
    bad = 0
    for name in SHARED_EXPORTS:
        if 'src/%s' % name not in src:
            errors.append('barrel 未导出 src/%s' % name)
            bad += 1
    print('  [6] barrel 导出       %s' % ('✓ 7 个模块齐全' if not bad else '✗ 缺 %d 个' % bad))


def c_brackets():
    bad = 0
    for d in CHECK_DIRS:
        for f in all_dart(d):
            depth = {'(': 0, '{': 0, '[': 0}
            pairs = {')': '(', '}': '{', ']': '['}
            for ch in strip_code(read(f)):
                if ch in '({[':
                    depth[ch] += 1
                elif ch in ')}]':
                    depth[pairs[ch]] -= 1
            left = {k: v for k, v in depth.items() if v != 0}
            if left:
                errors.append('括号不平衡 %s（%s）' % (left, os.path.relpath(f, ROOT)))
                bad += 1
    print('  [7] 括号平衡          %s' % ('✓ 全部平衡' if not bad else '✗ %d 个文件' % bad))


if __name__ == '__main__':
    print('仓库根: %s\n' % ROOT)
    c_imports()
    c_package_decl()
    c_shared_import()
    c_host_implements()
    c_foreign_symbols()
    c_barrel()
    c_brackets()
    print()
    if errors:
        print('发现 %d 个问题：' % len(errors))
        for e in errors:
            print('  - %s' % e)
        sys.exit(1)
    print('结构检查全部通过 ✓（注意：这不能替代 flutter analyze）')
