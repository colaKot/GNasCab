#!/usr/bin/env python3
"""Find missing packages in an installed node_modules tree.

Why: `electron-builder --dir` died with `Cannot find module '@develar/schema-utils'`.
Fix one, hit the next, fix that -- far too slow on a 1.2 GB / 27k-file tree sitting
on a slow drive. This walks every package.json under node_modules (including the
nested ones) and reports EVERY dependency that cannot be resolved, in one pass.

Resolution follows Node's algorithm closely enough: from a package directory, look
for `<dir>/node_modules/<name>`, then walk up to <project>/node_modules/<name>.

Usage:
  python tool/_dep_check.py <project_dir> [--only electron-builder,app-builder-lib]
  python tool/_dep_check.py <project_dir> --missing-only     # default
"""

import argparse
import json
import os
import sys

SKIP_DIRS = {".bin", ".cache", "test", "tests", "__tests__", "docs", "doc",
             "example", "examples", "demo", "samples"}


def pkg_json_paths(nm_dir):
    """Yield every package.json under a node_modules dir (recursively, so nested
    copies are covered too)."""
    for root, dirs, files in os.walk(nm_dir):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        if "package.json" in files:
            yield os.path.join(root, "package.json")
        # do not descend into a nested node_modules via os.walk twice; os.walk
        # already visits it, and we DO want those checked.


def resolve(name, from_dir, project_nm):
    """Is `name` resolvable from `from_dir`? Walk up looking in node_modules."""
    d = from_dir
    while True:
        cand = os.path.join(d, "node_modules", *name.split("/"))
        if os.path.isdir(cand) or os.path.isfile(cand + ".js"):
            return True
        parent = os.path.dirname(d)
        if parent == d or len(d) <= len(os.path.dirname(project_nm)):
            break
        d = parent
    cand = os.path.join(project_nm, *name.split("/"))
    return os.path.isdir(cand)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("project_dir")
    ap.add_argument("--only", default=None,
                    help="comma list of package names to restrict the walk to")
    a = ap.parse_args()

    proj = os.path.abspath(a.project_dir)
    nm = os.path.join(proj, "node_modules")
    if not os.path.isdir(nm):
        sys.exit("no node_modules in %s" % proj)

    only = set(x.strip() for x in a.only.split(",")) if a.only else None

    checked = 0
    missing = {}          # dep name -> sorted list of requiring packages
    for pj in pkg_json_paths(nm):
        pkg_dir = os.path.dirname(pj)
        rel = os.path.relpath(pkg_dir, nm)
        top = rel.split(os.sep)[0]
        if only and top not in only and not any(top.startswith(o) for o in only):
            continue
        try:
            with open(pj, "r", encoding="utf-8") as fh:
                meta = json.load(fh)
        except Exception:
            continue
        checked += 1
        deps = {}
        deps.update(meta.get("dependencies") or {})
        # optionalDependencies are ALLOWED to be absent; skip them.
        for dep in deps:
            if not resolve(dep, pkg_dir, nm):
                missing.setdefault(dep, set()).add(rel)

    print("checked %d package.json files" % checked)
    if not missing:
        print("OK: every declared dependency resolves")
        return 0
    print("\nMISSING (%d):" % len(missing))
    for dep in sorted(missing):
        who = sorted(missing[dep])
        print("  %-42s <- %s%s" % (dep, ", ".join(who[:3]),
                                   "" if len(who) <= 3 else " (+%d more)" % (len(who) - 3)))
    return 1


if __name__ == "__main__":
    sys.exit(main())
