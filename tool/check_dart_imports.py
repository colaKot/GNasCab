# -*- coding: utf-8 -*-
"""校验所有 Dart 相对 import 是否真实存在（不依赖 flutter/dart CLI）。"""
import os
import re
import sys

BASE = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
PAT = re.compile(r"""^\s*(?:import|export)\s+['"]((?:\.\./|\./)[^'"]+)['"]""", re.M)

bs = chr(92)
def norm(p):
    return p.replace(bs, "/")

bad = []
total = 0
files = 0
for dirpath, dirnames, filenames in os.walk(BASE):
    dirnames[:] = [d for d in dirnames if d not in ("build", ".dart_tool", ".git")]
    for fn in filenames:
        if not fn.endswith(".dart"):
            continue
        files += 1
        fp = os.path.join(dirpath, fn)
        try:
            content = open(fp, encoding="utf-8").read()
        except Exception:
            continue
        for m in PAT.finditer(content):
            rel = m.group(1)
            total += 1
            target = os.path.normpath(os.path.join(dirpath, rel))
            if not os.path.exists(target):
                bad.append((norm(fp), rel, norm(target)))

print("扫描 dart 文件: %d" % files)
print("相对引用总数: %d" % total)
print("无法解析: %d" % len(bad))
for fp, rel, t in bad[:80]:
    print("  %s" % fp)
    print("      -> %s   (解析到 %s)" % (rel, t))
