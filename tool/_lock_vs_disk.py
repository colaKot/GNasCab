#!/usr/bin/env python3
"""Compare package-lock.json against what is actually on disk in node_modules.

Why: `npm ls` (which electron-builder uses to build the dependency graph) reports
packages the lock declares but disk does not have -- with no `path` field -- and
app-builder-lib then dies with "dependency path is undefined". `@develar/schema-utils`
and `@anohanafes/offline-document-viewer` were both found this way, one at a time.

Reading the lock is near-instant (one file, a few hundred isdir calls) where walking
27k files on this drive takes minutes.

Usage:
  python tool/_lock_vs_disk.py <project_dir>
  python tool/_lock_vs_disk.py <project_dir> --prod-only    # skip dev-only entries
"""

import argparse
import json
import os
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("project_dir")
    ap.add_argument("--prod-only", action="store_true",
                    help="only report packages that are NOT marked dev-only in the lock")
    a = ap.parse_args()

    proj = os.path.abspath(a.project_dir)
    lock_path = os.path.join(proj, "package-lock.json")
    with open(lock_path, "r", encoding="utf-8") as fh:
        lock = json.load(fh)

    packages = lock.get("packages") or {}
    nm = os.path.join(proj, "node_modules")

    missing_prod, missing_dev, present, links = [], [], 0, []
    for key, entry in packages.items():
        if not key:
            continue                             # "" is the root package itself
        if not key.startswith("node_modules/"):
            continue                             # nested node_modules are covered by their own keys
        rel = key[len("node_modules/"):]
        path = os.path.join(nm, *rel.split("/"))
        if os.path.islink(path):
            links.append(rel)
        if os.path.isdir(path):
            present += 1
            continue
        (missing_dev if entry.get("dev") else missing_prod).append(rel)

    print("lock packages   : %d" % len(packages))
    print("present on disk : %d" % present)
    print("tmp links       : %s" % (", ".join(links) if links else "-"))
    print()

    def show(title, items):
        if not items:
            print("%s: none" % title)
            return
        print("%s (%d):" % (title, len(items)))
        for r in sorted(items):
            print("   ", r)

    show("MISSING (runtime)", missing_prod)
    if not a.prod_only:
        show("MISSING (dev-only)", missing_dev)

    return 1 if (missing_prod or (missing_dev and not a.prod_only)) else 0


if __name__ == "__main__":
    sys.exit(main())
