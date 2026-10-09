#!/usr/bin/env python3
"""Fetch the MDK SDK archive that the `fvp` Flutter plugin wants at build time.

Why this exists: `fvp/cmake/deps.cmake` downloads
  https://sourceforge.net/projects/mdk-sdk/files/nightly/mdk-sdk-windows-x64.7z
during CMake *configure*. From China that stalls forever. deps.cmake skips the
download entirely when the archive is already sitting at

  <pub cache>/hosted/<host>/fvp-<ver>/windows/mdk-sdk-windows-x64.7z

so the reliable fix is to fetch it once, through whatever proxy works, and drop
it there.

Usage (run through the build bridge so it uses the user's terminal/proxy):
  python tool/fetch_mdk_sdk.py --check
  python tool/fetch_mdk_sdk.py --proxy http://127.0.0.1:21578
  python tool/fetch_mdk_sdk.py --proxy http://127.0.0.1:21578 --url <mirror-url>

Output is pure ASCII on purpose: the bridge's cmd console is cp936, so Chinese
text would come back as mojibake.
"""

import argparse
import hashlib
import os
import sys
import time
import urllib.error
import urllib.request

DEFAULT_URL = (
    "https://sourceforge.net/projects/mdk-sdk/files/nightly/mdk-sdk-windows-x64.7z/download"
)
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
CHUNK = 256 * 1024


def default_out():
    base = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Pub", "Cache", "hosted")
    if not os.path.isdir(base):
        raise SystemExit("FATAL: pub cache not found at %s" % base)
    for host in sorted(os.listdir(base)):
        pkg_root = os.path.join(base, host)
        if not os.path.isdir(pkg_root):
            continue
        for name in sorted(os.listdir(pkg_root)):
            if name.startswith("fvp-") and os.path.isdir(os.path.join(pkg_root, name, "windows")):
                return os.path.join(pkg_root, name, "windows", "mdk-sdk-windows-x64.7z")
    raise SystemExit("FATAL: no fvp-* package with a windows/ dir under %s" % base)


def opener_for(proxy):
    handlers = []
    if proxy:
        handlers.append(urllib.request.ProxyHandler({"http": proxy, "https": proxy}))
    return urllib.request.build_opener(*handlers)


def human(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return "%.1f %s" % (n, unit)
        n /= 1024.0


def do_check(args):
    req = urllib.request.Request(args.url, method="HEAD")
    req.add_header("User-Agent", UA)
    t0 = time.time()
    try:
        with opener_for(args.proxy).open(req, timeout=args.timeout) as resp:
            size = resp.headers.get("Content-Length")
            print("HTTP %s in %.1fs" % (resp.status, time.time() - t0))
            print("final url    : %s" % resp.geturl())
            print("content-type : %s" % resp.headers.get("Content-Type"))
            print("length       : %s (%s bytes)" % (human(int(size)) if size else "?", size))
    except urllib.error.HTTPError as exc:
        print("HTTPError %s %s" % (exc.code, exc.reason))
        print("[hint] SourceForge answers 403 to bare HEAD from some proxies; use --probe (a small GET)")
        return 1
    except Exception as exc:  # noqa: BLE001
        print("FAILED: %s: %s" % (type(exc).__name__, exc))
        return 1
    return 0


def do_probe(args):
    """Tiny ranged GET: proves the proxy can actually pull bytes, not just connect."""
    req = urllib.request.Request(args.url)
    req.add_header("User-Agent", UA)
    req.add_header("Range", "bytes=0-262143")
    req.add_header("Accept", "*/*")
    t0 = time.time()
    try:
        with opener_for(args.proxy).open(req, timeout=args.timeout) as resp:
            head = resp.read(262144)
            dt = time.time() - t0
            print("HTTP %s in %.1fs" % (resp.status, dt))
            print("final url    : %s" % resp.geturl())
            print("content-type : %s" % resp.headers.get("Content-Type"))
            print("range        : %s" % resp.headers.get("Content-Range"))
            print("got          : %s in %.1fs  (%s/s)" % (
                human(len(head)), dt, human(len(head) / dt if dt else 0)))
            print("first bytes  : %r" % head[:160])
    except urllib.error.HTTPError as exc:
        print("HTTPError %s %s" % (exc.code, exc.reason))
        return 1
    except Exception as exc:  # noqa: BLE001
        print("FAILED: %s: %s" % (type(exc).__name__, exc))
        return 1
    return 0


def do_fetch(args):
    out = args.out or default_out()
    part = out + ".pypart"
    os.makedirs(os.path.dirname(out), exist_ok=True)

    done = os.path.getsize(part) if os.path.exists(part) else 0
    req = urllib.request.Request(args.url)
    req.add_header("User-Agent", UA)
    if done:
        req.add_header("Range", "bytes=%d-" % done)
        print("resuming at %s" % human(done))
    else:
        print("target: %s" % out)

    t0 = time.time()
    last = t0
    last_bytes = done
    h = hashlib.sha256()
    if done:
        with open(part, "rb") as fh:
            for blk in iter(lambda: fh.read(1 << 20), b""):
                h.update(blk)

    try:
        with opener_for(args.proxy).open(req, timeout=args.timeout) as resp:
            print("HTTP %s  %s" % (resp.status, resp.geturl()))
            total = resp.headers.get("Content-Length")
            total = (done + int(total)) if (total and resp.status == 206) else (
                int(total) if total else None)
            mode = "ab" if (done and resp.status == 206) else "wb"
            if mode == "wb":
                done = 0
                h = hashlib.sha256()
            with open(part, mode) as fh:
                while True:
                    blk = resp.read(CHUNK)
                    if not blk:
                        break
                    fh.write(blk)
                    h.update(blk)
                    done += len(blk)
                    now = time.time()
                    if now - last >= 1.0:
                        rate = (done - last_bytes) / (now - last)
                        if total:
                            print("  %s / %s  (%.1f%%)  %s/s" % (
                                human(done), human(total), done * 100.0 / total, human(rate)))
                        else:
                            print("  %s  %s/s" % (human(done), human(rate)))
                        last, last_bytes = now, done
    except Exception as exc:  # noqa: BLE001
        print("FAILED after %s: %s: %s" % (human(done), type(exc).__name__, exc))
        return 1

    print("downloaded   : %s in %.1fs" % (human(done), time.time() - t0))
    if total and done != total:
        print("WARNING: size mismatch, expected %d got %d -- keeping %s" % (total, done, part))
        return 1

    digest = h.hexdigest()
    print("sha256       : %s" % digest)
    if args.sha256 and args.sha256.lower() != digest:
        print("FAILED: sha256 mismatch (expected %s)" % args.sha256.lower())
        return 1

    os.replace(part, out)
    print("OK -> %s" % out)
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default=DEFAULT_URL)
    ap.add_argument("--out", default=None)
    ap.add_argument("--proxy", default=None, help="e.g. http://127.0.0.1:21578")
    ap.add_argument("--sha256", default=None)
    ap.add_argument("--timeout", type=float, default=60.0)
    ap.add_argument("--check", action="store_true", help="HEAD only, no download")
    ap.add_argument("--probe", action="store_true", help="ranged GET of 256 KiB, no full download")
    args = ap.parse_args()
    if args.check:
        return do_check(args)
    if args.probe:
        return do_probe(args)
    return do_fetch(args)


if __name__ == "__main__":
    sys.exit(main())
