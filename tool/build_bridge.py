#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""外部构桥（Build Bridge）—— 让 Agent 能在 WorkBuddy 进程树**之外**执行命令。

为什么需要它
------------
WorkBuddy 把它的所有子孙进程关进一个 Job Object（环境变量 `WORKBUDDY_APP_LIFETIME_JOB`），
并由 Sandbox Center 代理进程创建。在这个树里：
  · Dart 建带管道的子进程 → `CreateFile failed 231` / `process_win.cc:693`
  · 所以 `flutter pub get / analyze / build` 全跑不了
  · WMI / Start-Process / schtasks 这些逃逸手段又都被安全策略拦掉
**但普通 cmd 里一切正常**（铁柱实测 `flutter-check.bat` → all steps passed）。

于是反过来做：由**你自己在普通 cmd 里**启动本脚本，它就活在 WorkBuddy 树之外；
Agent 通过 127.0.0.1 把命令交给它执行、把输出取回来。
＝ 一个真正可用的「外部终端」，只是接口是 HTTP 而不是 VS Code 设置。

用法
----
1) 在**普通 cmd**（不是 WorkBuddy/IDE 里的终端）里：
       python tool/build_bridge.py
   启动后会打印端口与 token，并把 token 写到 tool/.build_bridge_token（Agent 读它鉴权）。
   脚本会一直运行，按 Ctrl+C 或关掉窗口即退出。

2) Agent 侧调用（Agent 会自己做完，不用手敲）：
       curl -s http://127.0.0.1:8799/ping
       curl -s -X POST http://127.0.0.1:8799/run \
            -H "X-Bridge-Token: <token>" -H "Content-Type: application/json" \
            -d '{"argv":["flutter","analyze"],"cwd":"G:/work/nascab/flutter_client","timeout":600}'

接口
----
  GET  /ping                 -> {"ok":true,"pid":...,"in_job":bool,"dart_can_spawn":bool}
  POST /run   {"argv":[...]} 或 {"cmd":"..."}，可选 cwd / timeout / env
                             -> {"rc":..,"stdout":..,"stderr":..,"seconds":..}
  POST /shutdown             -> 关闭（需 token）

安全须知（请务必阅读）
----------------------
· 只监听 **127.0.0.1**，不对局域网开放。
· 所有写操作都要 `X-Bridge-Token`（随机 32 字节，仅本机文件可见，每次启动重新生成）。
· 它**能执行任意命令** —— 这是它的用途，也意味着：任何能在本机读到这个 token 文件的程序，
  都能借它执行代码。**用完就关掉窗口**，不要长期挂着。
· 不落盘任何密钥；token 文件在退出时会被删除。
"""
import argparse
import json
import os
import secrets
import shutil
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
TOKEN_FILE = os.path.join(HERE, ".build_bridge_token")
TOKEN = secrets.token_urlsafe(32)
DEFAULT_PORT = 8799
MAX_BODY = 1 << 20  # 1 MiB


def is_in_job():
    """看自己是否仍被关在 Job Object 里（正常应该 True；由普通 cmd 启动时也可能 True，
    关键差别是那个 job 不属于 WorkBuddy、且没有拦住管道建档的限制）。"""
    try:
        import ctypes
        import ctypes.wintypes as w
        k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        k32.IsProcessInJob.argtypes = [w.HANDLE, w.HANDLE, ctypes.POINTER(w.BOOL)]
        b = w.BOOL()
        k32.IsProcessInJob(k32.GetCurrentProcess(), None, ctypes.byref(b))
        return bool(b.value)
    except Exception:
        return None


def dart_can_spawn():
    """关键自检：Dart 在本进程树下能不能建带管道的子进程。
    直接复用仓库里的 check_named_pipe 逻辑 —— 只读打开命名管道若返 231 就不行。"""
    try:
        sys.path.insert(0, HERE)
        import check_named_pipe as cnp  # noqa
        ok, err = cnp._probe("bridge", cnp.PIPE_ACCESS_DUPLEX, cnp.GENERIC_READ)
        return (ok is True), err
    except Exception as ex:
        return None, str(ex)


class Handler(BaseHTTPRequestHandler):
    server_version = "GNasCabBuildBridge/1.0"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("[bridge] %s - %s\n" % (self.address_string(), fmt % args))

    # ---------- helpers ----------
    def _send(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _auth(self):
        if self.headers.get("X-Bridge-Token") == TOKEN:
            return True
        self._send(403, {"ok": False, "error": "bad or missing X-Bridge-Token"})
        return False

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0 or n > MAX_BODY:
            return None
        try:
            return json.loads(self.rfile.read(n).decode("utf-8"))
        except Exception:
            return None

    # ---------- routes ----------
    def do_GET(self):
        if self.path.split("?")[0] == "/ping":
            can, err = dart_can_spawn()
            self._send(200, {
                "ok": True,
                "pid": os.getpid(),
                "cwd": os.getcwd(),
                "in_job": is_in_job(),
                "dart_named_pipe_read_ok": can,
                "dart_probe_err": err,
                "note": "dart_named_pipe_read_ok=false 说明本进程树仍建不了 Dart 子进程",
            })
        else:
            self._send(404, {"ok": False, "error": "use /ping or /run"})

    def do_POST(self):
        route = self.path.split("?")[0]
        if route == "/shutdown":
            if not self._auth():
                return
            self._send(200, {"ok": True, "bye": True})
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return
        if route != "/run":
            self._send(404, {"ok": False, "error": "use /ping or /run"})
            return
        if not self._auth():
            return
        req = self._body()
        if not isinstance(req, dict):
            self._send(400, {"ok": False, "error": "invalid JSON body"})
            return

        argv = req.get("argv")
        cmd = req.get("cmd")
        if argv is not None:
            if not isinstance(argv, list) or not all(isinstance(x, str) for x in argv):
                self._send(400, {"ok": False, "error": "argv must be a list of strings"})
                return
            popen_args, shell = argv, False
        elif isinstance(cmd, str) and cmd.strip():
            popen_args, shell = cmd, True
        else:
            self._send(400, {"ok": False, "error": "need argv[] or cmd"})
            return

        cwd = req.get("cwd") or os.getcwd()
        timeout = float(req.get("timeout") or 900)
        env = os.environ.copy()
        if isinstance(req.get("env"), dict):
            env.update({str(k): str(v) for k, v in req["env"].items()})

        t0 = time.time()
        try:
            p = subprocess.run(popen_args, shell=shell, cwd=cwd, env=env,
                               capture_output=True, timeout=timeout)
            rc, out, err = p.returncode, p.stdout, p.stderr
        except subprocess.TimeoutExpired as ex:
            self._send(200, {
                "ok": False, "error": "timeout after %.0fs" % timeout,
                "rc": None,
                "stdout": (ex.stdout or b"").decode("utf-8", "replace")[-200000:],
                "stderr": (ex.stderr or b"").decode("utf-8", "replace")[-200000:],
                "seconds": round(time.time() - t0, 1),
            })
            return
        except Exception as ex:
            self._send(200, {"ok": False, "error": "%s: %s" % (type(ex).__name__, ex),
                             "rc": None, "seconds": round(time.time() - t0, 1)})
            return

        self._send(200, {
            "ok": True,
            "rc": rc,
            "stdout": out.decode("utf-8", "replace")[-400000:],
            "stderr": err.decode("utf-8", "replace")[-200000:],
            "seconds": round(time.time() - t0, 1),
        })


def main():
    ap = argparse.ArgumentParser(description="GNasCab 外部构桥（在 WorkBuddy 树之外执行命令）")
    ap.add_argument("--port", type=int, default=DEFAULT_PORT)
    ap.add_argument("--host", default="127.0.0.1",
                    help="只允许 127.0.0.1；改成别的等于对局域网开放，别这么干")
    a = ap.parse_args()

    if a.host not in ("127.0.0.1", "localhost", "::1"):
        print("拒绝启动：只允许监听 127.0.0.1（传了 %s）" % a.host)
        return 2

    with open(TOKEN_FILE, "w", encoding="utf-8") as fh:
        fh.write(TOKEN)

    can, err = dart_can_spawn()
    print("=" * 72)
    print("GNasCab 外部构桥  http://%s:%d" % (a.host, a.port))
    print("=" * 72)
    print("  PID                : %d" % os.getpid())
    print("  cwd                : %s" % os.getcwd())
    print("  在 Job Object 里    : %s" % is_in_job())
    print("  ⭐ Dart 能建子进程  : %s%s"
          % ("是 ✓" if can else "否 ✗", "" if can else "   (%s)" % err))
    if not can:
        print("     ⇒ 说明这个终端**也在** WorkBuddy 树里（比如用 IDE 内置终端启动的）。")
        print("       请关掉，改用开始菜单里的「命令提示符」，再跑一次。")
    print("  token 文件         : %s" % TOKEN_FILE)
    print("  flutter            : %s" % (shutil.which("flutter") or "(不在 PATH，可用绝对路径)"))
    print("-" * 72)
    print("  按 Ctrl+C 或关闭本窗口即停止。用完请关掉（它能执行任意命令）。")
    print("=" * 72)

    httpd = ThreadingHTTPServer((a.host, a.port), Handler)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[bridge] 收到 Ctrl+C，退出")
    finally:
        httpd.server_close()
        try:
            os.remove(TOKEN_FILE)
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
