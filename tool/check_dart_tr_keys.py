# -*- coding: utf-8 -*-
"""校验指定 dart 文件里用到的 tr 文案键（'xxx'.tr / trParams）是否存在于 zh_cn.dart。"""
import re
import sys
import os

ZH = r"G:/work/nascab/flutter_client/lib/core/languages/zh_cn.dart"

keys_line = re.compile(r"^\s*'([^']+)'\s*:", re.M)
KNOWN = set(keys_line.findall(open(ZH, encoding="utf-8").read()))

use = re.compile(r"'([A-Za-z0-9_\.]+)'\s*\.tr(?:Params)?\s*\(")
use2 = re.compile(r"'([A-Za-z0-9_\.]+)'\s*\.tr\b")

missing = []
total = 0
for fp in sys.argv[1:]:
    if not os.path.isfile(fp):
        print("跳过（不存在）: %s" % fp)
        continue
    content = open(fp, encoding="utf-8").read()
    used = set(use.findall(content)) | set(use2.findall(content))
    for k in sorted(used):
        total += 1
        if k not in KNOWN:
            missing.append((fp, k))

print("检查文件数: %d" % len(sys.argv[1:]))
print("使用的 tr 键引用数: %d" % total)
print("语言包缺失的键: %d" % len(missing))
for fp, k in missing:
    print("  %s -> %s" % (fp.replace(chr(92), "/"), k))
