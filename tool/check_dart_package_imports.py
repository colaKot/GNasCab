#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Dart 包导入静态体检 —— 在跑不了 `flutter analyze` 的机器上替代它的第一层。

为什么需要它
------------
本机（Agent 进程树）里 Dart 无法创建子进程（`process_win.cc:693 ERROR_PIPE_BUSY`），
`flutter analyze` / `pub get` / `build bundle` 全都起不来。于是「analyze 会不会报
error」这件事，用**纯静态**方式自己回答：

  1. 读项目根的 `.dart_tool/package_config.json`（=`flutter pub get` 的产物）；
  2. 枚举项目下所有 `.dart`；
  3. **按 analyzer 的真实规则**算出哪些文件被排除
     （就近优先 nearest-config-wins；exclude 的 glob 相对于所在配置文件目录）；
  4. 对未被排除的文件，解析 `import` / `export` 里的 `package:<name>/<path>`，
     核对该 name 在 package_config 里、且目标文件真实存在。

命中「未解析的 package 导入」⇒ `flutter analyze` 必然报 error（这正是
`packages/audio_service/example/` 那个坑的形态）。

⚠️ 它**不替代** `flutter analyze`：类型错误、语法错误、`part` 断链、lint 都查不出来。
真正的闸门仍是 `flutter build bundle`。

用法：
  python tool/check_dart_package_imports.py                    # 默认四个客户端
  python tool/check_dart_package_imports.py flutter_client ...  # 指定项目
  python tool/check_dart_package_imports.py --all-dirs          # 连被排除的文件也列出（信息用）

退出码非 0 表示发现未解析导入。
"""

import fnmatch
import json
import os
import posixpath
import re
import sys
from urllib.parse import unquote, urlparse

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DEFAULT_PROJECTS = ["flutter_client", "photo_client", "music_client", "sync_client"]

SKIP_DIR_PARTS = {
    "node_modules", ".git", "build", ".dart_tool", ".gradle", ".idea",
    "oh_modules", ".hvigor", "Pods", ".cxx", "captures", "ephemeral",
    "DerivedData", ".devdata",
}

IMPORT_RE = re.compile(r"""^\s*(?:import|export)\s+['"]([^'"]+)['"]""", re.MULTILINE)
PART_RE = re.compile(r"""^\s*part\s+['"]([^'"]+)['"]""", re.MULTILINE)


def _uri_normpath(base_segments, uri):
    """按 **URI 语义**解析相对引用（不是文件系统语义）。

    ⭐ 关键差异：URI 引用**不能越过基准向上逃逸**，多余的 `../` 会被静默吞掉。
        基准 `package:WaterNasOS/core/user/` + `../../../core/api/x.dart`
        -> `package:WaterNasOS/core/api/x.dart`
    而 `os.path.normpath` 会逃逸到 `<项目根>/core/api/x.dart`（不存在）—— **误报的根源**。
    做法：把基准拼成以 `/` 开头的绝对 POSIX 路径，再 normpath；
    `posixpath.normpath('/a/../../b')` == `/b`，正好复现「越不过根」。
    """
    joined = posixpath.normpath(posixpath.join("/", base_segments, uri))
    return joined.lstrip("/")


def resolve_relative(project, file_abs, uri):
    """返回相对 URI 应指向的真实路径（按 URI 语义解析，见 _uri_normpath）。"""
    rel = os.path.relpath(os.path.abspath(file_abs), project).replace(os.sep, "/")
    if rel.startswith("lib/"):
        # 库 URI = package:<name>/<lib 之下那一段>，越不过 package 根
        base = posixpath.dirname(rel[len("lib/"):])
        inner = _uri_normpath(base, uri)
        return os.path.normpath(os.path.join(project, "lib", inner.replace("/", os.sep)))
    # lib/ 之外（test/ 等）：基准是文件所在目录，越不过盘根
    drive, tail = os.path.splitdrive(os.path.abspath(file_abs))
    inner = _uri_normpath(posixpath.dirname(tail.replace(os.sep, "/")), uri)
    return os.path.normpath(drive + os.sep + inner.replace("/", os.sep))


def glob_to_re(pat):
    """把 Dart analyzer 用的 glob 翻成正则。** 跨目录，* 不跨目录。"""
    out = []
    i = 0
    while i < len(pat):
        c = pat[i]
        if c == "*":
            if pat[i:i + 2] == "**":
                out.append(".*")
                i += 2
                continue
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(c))
        i += 1
    return re.compile("^" + "".join(out) + "$")


def to_path(uri, base_dir):
    """package_config 里的 rootUri（可能是相对路径 / file: URI）-> 本地绝对路径。"""
    if uri.startswith("file:"):
        p = unquote(urlparse(uri).path)
        if re.match(r"^/[A-Za-z]:", p):
            p = p[1:]
        return os.path.normpath(p)
    return os.path.normpath(os.path.join(base_dir, uri))


def load_package_config(project):
    cfg_path = os.path.join(project, ".dart_tool", "package_config.json")
    if not os.path.isfile(cfg_path):
        return None, cfg_path
    with open(cfg_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    base = os.path.dirname(cfg_path)
    pkgs = {}
    for p in data.get("packages", []):
        root = to_path(p.get("rootUri", ""), base)
        pkg_uri = p.get("packageUri", "lib/")
        pkgs[p["name"]] = os.path.normpath(os.path.join(root, pkg_uri))
    return pkgs, cfg_path


def find_options_files(project):
    """项目下所有 analysis_options.yaml：{目录绝对路径: [glob, ...]}"""
    found = {}
    for dirpath, dirs, files in os.walk(project):
        dirs[:] = [d for d in dirs if d not in SKIP_DIR_PARTS]
        for name in files:
            if name != "analysis_options.yaml":
                continue
            path = os.path.join(dirpath, name)
            globs = []
            try:
                import yaml
                with open(path, "r", encoding="utf-8") as fh:
                    data = yaml.safe_load(fh) or {}
                globs = list((data.get("analyzer") or {}).get("exclude") or [])
            except ImportError:
                globs = _exclude_by_regex(path)
            except Exception as e:                      # 配置坏了也要看得见
                print("   [warn] 解析失败 %s: %s" % (path, e))
            found[dirpath] = globs
    return found


def _exclude_by_regex(path):
    """没有 pyyaml 时的兜底：只抓 analyzer.exclude 下面 `- xxx` 那几行。"""
    globs, in_exclude, base_indent = [], False, None
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            if re.match(r"^(\s*)exclude:\s*$", line):
                in_exclude, base_indent = True, len(line) - len(line.lstrip())
                continue
            if in_exclude:
                m = re.match(r"^(\s*)-\s*(.+?)\s*$", line)
                if m and len(m.group(1)) > base_indent:
                    globs.append(m.group(2).strip("'\""))
                elif line.strip() and not line.startswith(" " * (base_indent + 1)):
                    in_exclude = False
    return globs


def governing_exclude(dart_file, project, options):
    """就近优先：从文件所在目录往上找第一个 analysis_options.yaml（不超过项目根）。"""
    d = os.path.dirname(os.path.abspath(dart_file))
    project_abs = os.path.abspath(project)
    while True:
        if d in options:
            base = d
            rel = os.path.relpath(os.path.abspath(dart_file), base).replace(os.sep, "/")
            for g in options[d]:
                if glob_to_re(g).match(rel):
                    return rel, g, os.path.relpath(base, REPO).replace(os.sep, "/")
            return None, None, None
        if os.path.normcase(d) == os.path.normcase(project_abs):
            return None, None, None
        parent = os.path.dirname(d)
        if parent == d:
            return None, None, None
        d = parent


def scan(project, show_excluded=False):
    project = os.path.abspath(project)
    name = os.path.basename(project)
    print("=" * 68)
    print("工程 %s" % name)
    print("=" * 68)

    pkgs, cfg = load_package_config(project)
    if pkgs is None:
        print("   [SKIP] 没有 %s —— 先跑一次 `flutter pub get`" % os.path.relpath(cfg, REPO))
        return None

    options = find_options_files(project)
    print("   package_config: %d 个包；analysis_options: %d 份（就近优先）"
          % (len(pkgs), len(options)))

    n_files = n_skip = n_imp = 0
    bad = []
    excluded = []

    for dirpath, dirs, files in os.walk(project):
        dirs[:] = [d for d in dirs if d not in SKIP_DIR_PARTS]
        for fn in files:
            if not fn.endswith(".dart"):
                continue
            f = os.path.join(dirpath, fn)
            n_files += 1
            rel, why, cfg_dir = governing_exclude(f, project, options)
            if rel is not None:
                n_skip += 1
                excluded.append((os.path.relpath(f, project).replace(os.sep, "/"), why, cfg_dir))
                continue

            try:
                with open(f, "r", encoding="utf-8", errors="replace") as fh:
                    src = fh.read()
            except OSError as e:
                bad.append((os.path.relpath(f, project), "<读取失败 %s>" % e, "?"))
                continue

            for m in list(IMPORT_RE.finditer(src)) + list(PART_RE.finditer(src)):
                uri = m.group(1)
                line = src[:m.start()].count("\n") + 1
                n_imp += 1
                if uri.startswith("dart:"):
                    continue
                if uri.startswith("package:"):
                    tail = uri[len("package:"):]
                    pkg_name, _, rest = tail.partition("/")
                    if pkg_name not in pkgs:
                        bad.append((os.path.relpath(f, project).replace(os.sep, "/"),
                                    "package:%s 不在 package_config 里" % pkg_name, line))
                        continue
                    target = os.path.join(pkgs[pkg_name], rest.replace("/", os.sep))
                    if not os.path.isfile(target):
                        bad.append((os.path.relpath(f, project).replace(os.sep, "/"),
                                    "package:%s 指向的文件不存在: %s" % (pkg_name, rest), line))
                    continue
                # 相对 URI（按 URI 语义解析，多余的 ../ 会被吞掉，别用 os.path）
                target = resolve_relative(project, f, uri)
                if not os.path.isfile(target):
                    bad.append((os.path.relpath(f, project).replace(os.sep, "/"),
                                "相对路径不存在: %s  (-> %s)" % (uri, target), line))

    print("   dart 文件 %d 个（被 analyzer.exclude 排除 %d 个）" % (n_files, n_skip))
    if show_excluded and excluded:
        for p, why, cfg_dir in excluded:
            print("      [excluded by %s: %s]  %s" % (cfg_dir, why, p))
    print("   导入/导出/part 语句 %d 条" % n_imp)

    if bad:
        print("\n   未解析 %d 处 —— `flutter analyze` 会报 ERROR：" % len(bad))
        for p, why, line in bad[:40]:
            print("      %s:%s  %s" % (p, line, why))
        if len(bad) > 40:
            print("      ...（还有 %d 处）" % (len(bad) - 40))
    else:
        print("\n   未被排除的文件里，package / 相对导入**全部解析成功** ✓")
    print()
    return bad


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    show_excluded = "--all-dirs" in sys.argv
    projects = [os.path.join(REPO, a) for a in args] or \
               [os.path.join(REPO, a) for a in DEFAULT_PROJECTS]

    print()
    print("#" * 68)
    print("# Dart 包导入静态体检（替代 analyze 的第一层，不替代 build bundle）")
    print("#" * 68)

    total = 0
    skipped = 0
    for p in projects:
        if not os.path.isdir(p):
            print("=" * 68)
            print("工程 %s\n   [SKIP] 目录不存在" % os.path.basename(p))
            skipped += 1
            continue
        bad = scan(p, show_excluded)
        if bad is None:
            skipped += 1
        else:
            total += len(bad)

    print("=" * 68)
    print("汇总：未解析导入 %d 处；跳过 %d 个工程" % (total, skipped))
    print("=" * 68)
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
