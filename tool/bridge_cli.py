#!/usr/bin/env python3
"""Thin client for tool/build_bridge.py.

The bridge is a tiny HTTP server that MUST be started by the user from a NORMAL
cmd window (see tool/build-bridge.bat), because processes launched from the
WorkBuddy process tree cannot create inheritable pipes (CreateFileW on a
named pipe opened read-only returns 231 there).

Usage:
  python tool/bridge_cli.py ping
  python tool/bridge_cli.py run [--cwd DIR] [--timeout SEC] -- <argv...>
  python tool/bridge_cli.py run [--cwd DIR] [--timeout SEC] --shell "<command line>"
  python tool/bridge_cli.py shutdown

argv mode spawns the process directly (no shell), so it CANNOT launch a .bat/.cmd
shim -- flutter, dart, gradlew, hvigorw are all shims here, and you get a bare
`FileNotFoundError: [WinError 2]`. Use --shell for those, and give the FULL path
(the user's cmd window does not necessarily have flutter on PATH):
  --shell "G:\\work\\_toolchain\\flutter-sdk\\flutter\\bin\\flutter.bat build windows --release"

Exit code: the remote command's rc (for `run`), 0/1 for the rest.
"""

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOKEN_FILE = HERE / ".build_bridge_token"
DEFAULT_PORT = 8799


def load_token():
    if not TOKEN_FILE.exists():
        sys.exit(
            "FATAL: %s not found -- is the bridge running?\n"
            "Ask the user to run tool\\build-bridge.bat in a normal cmd window." % TOKEN_FILE
        )
    tok = TOKEN_FILE.read_text(encoding="utf-8").strip()
    if not tok:
        sys.exit("FATAL: token file is empty")
    return tok


def call(port, path, payload=None, timeout=3600):
    url = "http://127.0.0.1:%d%s" % (port, path)
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="GET" if data is None else "POST")
    req.add_header("X-Bridge-Token", load_token())
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        sys.exit("HTTP %d from bridge: %s" % (exc.code, body))
    except Exception as exc:  # noqa: BLE001
        sys.exit("Cannot reach bridge on port %d (%r). Is that cmd window still open?" % (port, exc))


def out(text):
    """Write raw utf-8 bytes so a cp936 console cannot blow up mid-run."""
    sys.stdout.buffer.write(text.encode("utf-8", "replace"))
    sys.stdout.buffer.flush()


def cmd_ping(args):
    r = call(args.port, "/ping", timeout=30)
    out(json.dumps(r, ensure_ascii=False, indent=2) + "\n")
    return 0 if r.get("ok") else 1


def cmd_run(args):
    if args.shell is None and not args.argv:
        sys.exit("FATAL: give either `-- <argv...>` or `--shell \"<cmd>\"`")
    payload = {}
    if args.shell is not None:
        payload["cmd"] = args.shell
    else:
        payload["argv"] = args.argv
    if args.cwd:
        payload["cwd"] = args.cwd
    if args.timeout:
        payload["timeout"] = args.timeout
    r = call(args.port, "/run", payload, timeout=(args.timeout or 3600) + 60)
    if r.get("error"):
        # The bridge reports spawn failures as {"ok": false, "error": ..., "rc": null}.
        # Without this the caller only sees `rc=None  0.0s`, which looks like a silent
        # no-op instead of "the process never started".
        out("--- bridge error ---\n%s\n" % r["error"])
    if r.get("stdout"):
        out(r["stdout"] if r["stdout"].endswith("\n") else r["stdout"] + "\n")
    if r.get("stderr"):
        out("--- stderr ---\n" + r["stderr"] if not r["stderr"].endswith("\n") else "--- stderr ---\n" + r["stderr"])
    out("=== rc=%s  %.1fs ===\n" % (r.get("rc"), r.get("seconds", 0)))
    return int(r.get("rc") or 0)


def cmd_shutdown(args):
    r = call(args.port, "/shutdown", {}, timeout=30)
    out(json.dumps(r, ensure_ascii=False) + "\n")
    return 0


def main():
    p = argparse.ArgumentParser(prog="bridge_cli.py")
    p.add_argument("--port", type=int, default=DEFAULT_PORT)
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("ping").set_defaults(func=cmd_ping)
    sub.add_parser("shutdown").set_defaults(func=cmd_shutdown)

    r = sub.add_parser("run")
    r.add_argument("--cwd")
    r.add_argument("--timeout", type=float)
    r.add_argument("--shell", default=None)
    r.add_argument("argv", nargs="*")
    r.set_defaults(func=cmd_run)

    args = p.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
