#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""行尾符守卫。

起因：本仓库的 .bat 历来都是 CRLF，而编辑器/工具新写的 .bat 很容易落成 LF。

⚠️ 但请**不要**相信"LF 行尾会让 cmd.exe 解析错位"这个流行说法 —— 它已被实测推翻：
同样内容的 LF 版与 CRLF 版简单批处理都能完整跑完（14 次调用、0 条假命令），
真实脚本也解析正常。所以本守卫要求 .bat 为 CRLF，理由只是"与既有文件保持一致、
避免编辑器反复翻转行尾"，**不是**"否则会报错"。

真正被证实的 cmd 坑是另一个（不在本脚本职责内，仅记于此）：
`for` 块内的 `echo` 里出现 `(` `)` 必须写成 `^(` `^)`，去掉会**直接打断循环**。

规则：
  *.bat / *.cmd   -> 必须 CRLF（Windows 命令行，仓库既有风格）
  *.sh            -> 必须 LF  （POSIX shell）
  *.dart          -> 允许 CRLF 或 LF，但同一文件内必须统一（不许混用）

作用域：默认只看 `tool/`（自己的脚本）。加 --repo 才全仓扫描；且 --repo 下
禁止 --fix，只报告，避免误改上游文件（模板自带的 .sh 就是 CRLF，不该动）。

用法：
  python tool/check_eol.py              # 只检查 tool/，报告异常
  python tool/check_eol.py --fix        # 顺带修正 tool/ 下 bat/sh 的行尾
  python tool/check_eol.py --repo       # 全仓只读扫描
  python tool/check_eol.py --repo --all # 连 .dart 行尾混用一起查

退出码非 0 表示有问题。
"""

import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(REPO, "tool")

SKIP_DIR_PARTS = {
    "node_modules", ".git", "build", ".dart_tool", ".gradle",
    "oh_modules", ".hvigor", "Pods", ".cxx", "captures",
    "ephemeral", "DerivedData", ".devdata", ".backup_sync_20261001_082533",
}

# 上游/模板自带文件，行尾由上游决定，不参与检查（避免噪音，也避免误改）
UPSTREAM_EXEMPT = {
    "flutter_client/ios/scripts/generate_third_party_dsyms.sh",
}

SCANNED = {"bat": 0, "sh": 0, "dart": 0}


def rel(p):
    return os.path.relpath(p, REPO).replace("\\", "/")


def walk(exts, root=TOOL, allmode=False):
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIR_PARTS]
        for name in files:
            full = os.path.join(dirpath, name)
            if rel(full) in UPSTREAM_EXEMPT:
                continue
            if os.path.splitext(name)[1].lower() in exts:
                yield full
            elif allmode and name.lower().endswith(".dart"):
                yield full


def eol_stats(path):
    with open(path, "rb") as fh:
        b = fh.read()
    crlf = b.count(b"\r\n")
    lf = b.count(b"\n") - crlf
    cr = b.count(b"\r") - crlf
    return crlf, lf, cr


def to_crlf(path):
    with open(path, "rb") as fh:
        b = fh.read()
    b = b.replace(b"\r\n", b"\n").replace(b"\r", b"\n").replace(b"\n", b"\r\n")
    with open(path, "wb") as fh:
        fh.write(b)


def to_lf(path):
    with open(path, "rb") as fh:
        b = fh.read()
    b = b.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    with open(path, "wb") as fh:
        fh.write(b)


def main():
    argv = sys.argv[1:]
    repomode = "--repo" in argv
    fix = ("--fix" in argv) and not repomode
    allmode = "--all" in argv
    root = REPO if repomode else TOOL

    fails = []
    fixed = []

    for path in walk({".bat", ".cmd"}, root):
        SCANNED["bat"] += 1
        crlf, lf, cr = eol_stats(path)
        if crlf == 0 and (lf or cr):
            fails.append((rel(path), "bat 不是 CRLF", crlf, lf, cr))
            if fix:
                to_crlf(path)
                fixed.append(rel(path))
        elif lf:
            fails.append((rel(path), "bat 行尾混用（含裸 LF）", crlf, lf, cr))

    for path in walk({".sh"}, root):
        SCANNED["sh"] += 1
        crlf, lf, cr = eol_stats(path)
        if crlf or cr:
            fails.append((rel(path), "sh 不是纯 LF", crlf, lf, cr))
            if fix:
                to_lf(path)
                fixed.append(rel(path))

    if allmode:
        for path in walk(set(), root, allmode=True):
            if not path.lower().endswith(".dart"):
                continue
            SCANNED["dart"] += 1
            crlf, lf, cr = eol_stats(path)
            if crlf and lf:
                fails.append((rel(path), "dart 行尾混用", crlf, lf, cr))

    print("=" * 68)
    print("行尾符守卫  作用域=%s%s%s" % (
        "全仓（只读）" if repomode else "tool/",
        "  --fix" if fix else "",
        "  --all" if allmode else ""))
    print("=" * 68)
    print("已扫描：bat/cmd=%d  sh=%d%s" % (
        SCANNED["bat"], SCANNED["sh"],
        "  dart=%d" % SCANNED["dart"] if allmode else ""))
    if repomode and "--fix" in argv:
        print("提示：--repo 模式下忽略 --fix，避免误改上游文件。")

    if fixed:
        print("\n已修正 %d 个文件：" % len(fixed))
        for f in fixed:
            print("   fixed  %s" % f)

    remaining = []
    for path, why, crlf, lf, cr in fails:
        if fix and path in fixed:
            continue
        remaining.append((path, why, crlf, lf, cr))

    if remaining:
        print("\n仍有问题 %d 处：" % len(remaining))
        for path, why, crlf, lf, cr in remaining:
            print("   FAIL  %-62s %s  (CRLF=%d LF=%d CR=%d)" % (path, why, crlf, lf, cr))
    else:
        print("\n全部通过 ✓")

    print("---- 失败 %d / 命中问题 %d" % (len(remaining), len(fails)))
    return 1 if remaining else 0


if __name__ == "__main__":
    sys.exit(main())
