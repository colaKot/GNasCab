#!/usr/bin/env python3
"""Fetch ONE npm package (exact version + sha512) and unpack it into node_modules.

Why not `npm install`: this repo's node_modules is 1.2 GB / 27k files on a slow
drive, and package.json has `postinstall: npx @electron/rebuild`, so a reify would
rebuild 7 native modules for a single missing directory. Downloading that one
tarball is ~10 KB and touches nothing else.

The tarball URL + integrity are read from package-lock.json, so the result is
byte-identical to what `npm ci` would have produced.

Usage:
  python tool/_npm_fetch_pkg.py --project electron_server --name @develar/schema-utils
  python tool/_npm_fetch_pkg.py --project electron_server --name @develar/schema-utils --dry-run
  python tool/_npm_fetch_pkg.py --project . --name ajv --version 6.12.6 --force

Needs network. From the agent tree that means `dangerouslyDisableSandbox`, or run
it through the build bridge (工具/构桥), which lives in a normal cmd.
"""

import argparse
import base64
import hashlib
import io
import json
import os
import shutil
import sys
import tarfile
import urllib.request

UA = "GNasCab-dep-fix/1.0"


def load_lock_entry(project, name):
    lock_path = os.path.join(project, "package-lock.json")
    if not os.path.isfile(lock_path):
        sys.exit("no package-lock.json in %s" % project)
    with open(lock_path, "r", encoding="utf-8") as fh:
        lock = json.load(fh)
    pkgs = lock.get("packages") or {}
    key = "node_modules/" + name
    e = pkgs.get(key)
    if e is None:
        sys.exit("package-lock.json has no entry %r" % key)
    return e, lock.get("lockfileVersion")


def download(url, proxy=None):
    handlers = []
    if proxy:
        handlers.append(urllib.request.ProxyHandler({"http": proxy, "https": proxy}))
    opener = urllib.request.build_opener(*handlers)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with opener.open(req, timeout=120) as resp:
        return resp.read()


def verify(blob, integrity):
    if not integrity:
        return "no integrity in lock (skipped)"
    algo, _, b64 = integrity.partition("-")
    if not b64:
        return "unparsable integrity, skipped"
    got = base64.b64encode(hashlib.new(algo, blob).digest()).decode()
    if got != b64:
        raise SystemExit("INTEGRITY MISMATCH for %s:\n  want %s\n  got  %s" % (algo, b64, got))
    return "%s OK" % algo


def unpack(blob, dest):
    """npm tarballs wrap everything in a top-level `package/` dir."""
    tmp = dest + ".tmp-unpack"
    if os.path.isdir(tmp):
        shutil.rmtree(tmp)
    os.makedirs(tmp, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz") as tf:
        names = tf.getnames()
        if not names or not all(n == "package" or n.startswith("package/") for n in names):
            raise SystemExit("unexpected tarball layout, first entry: %r" % (names[:1],))
        for m in tf.getmembers():
            m.name = m.name[len("package"):].lstrip("/")
        try:
            tf.extractall(tmp, filter="data")
        except TypeError:                      # Python < 3.12
            tf.extractall(tmp)
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    shutil.move(tmp, dest)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", required=True)
    ap.add_argument("--name", required=True, help="e.g. @develar/schema-utils")
    ap.add_argument("--version", default=None, help="default: take from lock")
    ap.add_argument("--url", default=None, help="default: take from lock")
    ap.add_argument("--proxy", default=None, help="e.g. http://127.0.0.1:21578")
    ap.add_argument("--dest-nm", default=None, help="default: <project>/node_modules")
    ap.add_argument("--force", action="store_true", help="replace an existing dir")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    proj = os.path.abspath(a.project)
    entry, lockver = load_lock_entry(proj, a.name) if not a.url else ({}, None)

    version = a.version or entry.get("version")
    url = a.url or entry.get("resolved")
    integrity = entry.get("integrity")
    if not url:
        sys.exit("no resolved URL (pass --url)")

    nm = a.dest_nm or os.path.join(proj, "node_modules")
    dest = os.path.join(nm, *a.name.split("/"))

    print("package   : %s@%s" % (a.name, version))
    print("url       : %s" % url)
    print("integrity : %s" % (integrity or "(none)"))
    print("dest      : %s" % dest)
    print("state     : %s" % ("EXISTS" if os.path.isdir(dest) else "missing"))
    if os.path.isdir(dest) and not a.force:
        print("\nalready present; pass --force to replace. nothing to do.")
        return 0
    if a.dry_run:
        print("\n(dry-run: not downloading)")
        return 0

    print("\ndownloading...")
    blob = download(url, a.proxy)
    print("  %d bytes" % len(blob))
    print("  sha512: %s" % verify(blob, integrity))
    unpack(blob, dest)
    print("  unpacked -> %s" % dest)

    pj = os.path.join(dest, "package.json")
    if os.path.isfile(pj):
        with open(pj, "r", encoding="utf-8") as fh:
            meta = json.load(fh)
        print("  %s@%s (main=%s)" % (meta.get("name"), meta.get("version"),
                                     meta.get("main") or meta.get("exports") or "-"))
    print("\nDONE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
