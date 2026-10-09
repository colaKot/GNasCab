#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""在「flutter 工具链跑不起来」的机器上，直接驱动 Dart analysis_server 做静态分析。

为什么需要它
------------
本机（Agent 进程树）里 Dart 无法创建子进程：
    CreateFile failed 231
    ProcessException: 所有的管道范例都在使用中。 (process_win.cc:693)
而 `flutter analyze` 与 `dart analyze` **都要**去起子进程
（`dartaotruntime.exe analysis_server_aot.dart.snapshot`）⇒ 两者都当场崩。

但是：**Python 建子进程完全正常。** 于是反过来做 —— 由 Python 持有管道，
把 Dart SDK 自带的 analysis_server 拉起来，按官方 legacy protocol 驱动它。
拿到的诊断就是 `dart analyze` 会报的那一批（同一份服务器、同一套 analysis_options 规则）。

协议要点（踩过的坑）
--------------------
- `server.connected` 是服务器主动发的第一帧，收到即握手完成。
- **请求 id 必须是字符串**（`"1"`）；给整数会得到 `INVALID_REQUEST`。
- `analysis.setAnalysisRoots` 的 `included` 用**本地路径**，不用 file:// URI。
- `analysis.setSubscriptions` 订阅 `ERRORS` 后，服务器会按文件主动推送 `analysis.errors`。
  ⭐ **干净文件也会推送**（`errors` 是空数组）—— 实测 photo_client 只有 1 个 dart 文件，
  却收到 7 条推送（多出来的是传递依赖进去的库/框架文件）。所以：
  这是「一次完整分析已经跑过哪些文件」的可靠信号，也是判定分析结束的依据。
- ❗`analysis.analyzedFiles` 在本版服务器上**不会发出**（实测 60s 内 0 次）。
  所以**不能**靠它看 `analyzer.exclude` 是否生效；push 模式下验证 exclude 只能看
  「被排除目录里的文件一条诊断都不出现」这个**缺席证据**。

用法：
  python tool/dart_analyze.py flutter_client
  python tool/dart_analyze.py flutter_client --fatal-warnings
  python tool/dart_analyze.py . --sdk D:/path/to/dart-sdk --json out.json

退出码：有 ERROR 即 1（加 --fatal-warnings 时 WARNING 也算）。
"""

import argparse
import json
import os
import subprocess
import sys
import threading
import time

DEFAULT_SDK = r"G:\work\_toolchain\flutter-sdk\flutter\bin\cache\dart-sdk"

SEV_ORDER = {"ERROR": 0, "WARNING": 1, "INFO": 2}

SKIP_DIR_PARTS = {
    "node_modules", ".git", "build", ".dart_tool", ".gradle", ".idea",
    "oh_modules", ".hvigor", "Pods", ".cxx", "captures", "ephemeral",
    "DerivedData", ".devdata",
}


def find_sdk(explicit):
    for cand in (explicit, os.environ.get("DART_SDK")):
        if cand and os.path.isfile(os.path.join(cand, "bin", "dartaotruntime.exe")):
            return cand
    root = os.environ.get("FLUTTER_ROOT")
    if root:
        cand = os.path.join(root, "bin", "cache", "dart-sdk")
        if os.path.isfile(os.path.join(cand, "bin", "dartaotruntime.exe")):
            return cand
    if os.path.isfile(os.path.join(DEFAULT_SDK, "bin", "dartaotruntime.exe")):
        return DEFAULT_SDK
    return None


def uri_to_path(uri):
    if uri.startswith("file:"):
        from urllib.parse import unquote, urlparse
        p = unquote(urlparse(uri).path)
        if len(p) > 2 and p[0] == "/" and p[2] == ":":
            p = p[1:]
        return p.replace("/", os.sep)
    return uri


class Server:
    def __init__(self, sdk, cwd, verbose=False):
        self.sdk = sdk
        self.verbose = verbose
        self.responses = {}
        self.notifications = []
        self.lock = threading.Lock()
        self.analyzed_files = None
        self.errors_by_file = {}
        self.not_analyzed = {}
        self.errors_events = 0          # 收到的 analysis.errors 事件数（含空数组，单调递增）
        self.last_push_at = 0.0         # 最近一次推送的时间戳
        self._next_id = 0
        self.closed = False

        args = [
            os.path.join(sdk, "bin", "dartaotruntime.exe"),
            os.path.join(sdk, "bin", "snapshots", "analysis_server_aot.dart.snapshot"),
            "--client-id=gnascab-dart-analyze",
            "--disable-server-feature-completion",
            "--disable-server-feature-search",
            "--disable-status-notification-debouncing",
            "--disable-silent-analysis-exceptions",
            "--sdk", sdk,
        ]
        self.proc = subprocess.Popen(
            args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, cwd=cwd,
        )
        self._t = threading.Thread(target=self._reader, daemon=True)
        self._t.start()

    def _reader(self):
        for raw in self.proc.stdout:
            line = raw.decode("utf-8", "replace").strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except ValueError:
                if self.verbose:
                    print("[server-raw] " + line[:200], file=sys.stderr)
                continue
            if "event" in msg:
                self._on_event(msg)
            else:
                with self.lock:
                    self.responses[str(msg.get("id"))] = msg
            if self.verbose:
                print("[srv] " + line[:200], file=sys.stderr)

    def _on_event(self, msg):
        ev = msg.get("event")
        params = msg.get("params") or {}
        if ev == "analysis.analyzedFiles":
            self.analyzed_files = [uri_to_path(d) for d in params.get("directories", [])]
        elif ev == "analysis.errors":
            f = uri_to_path(params.get("file", ""))
            with self.lock:
                self.errors_by_file[f] = params.get("errors") or []
                self.errors_events += 1
                self.last_push_at = time.time()
        elif ev == "server.error":
            print("[server.error] %s" % params.get("message"), file=sys.stderr)

    def send(self, method, params=None):
        self._next_id += 1
        rid = str(self._next_id)
        req = {"jsonrpc": "2.0", "id": rid, "method": method}
        if params is not None:
            req["params"] = params
        self.proc.stdin.write((json.dumps(req) + "\n").encode("utf-8"))
        self.proc.stdin.flush()
        return rid

    def wait(self, rid, timeout):
        deadline = time.time() + timeout
        while time.time() < deadline:
            with self.lock:
                if rid in self.responses:
                    return self.responses.pop(rid)
            time.sleep(0.01)
        return None

    def wait_for(self, cond, timeout):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if cond():
                return True
            time.sleep(0.02)
        return False

    def close(self):
        if not self.closed:
            self.closed = True
            try:
                self.proc.kill()
            except Exception:
                pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path", nargs="?", default=".")
    ap.add_argument("--sdk", default=None)
    ap.add_argument("--fatal-warnings", action="store_true")
    ap.add_argument("--json", default=None, help="把原始诊断写到这里")
    ap.add_argument("--quiet-files", action="store_true", help="不逐文件报进度")
    ap.add_argument("--timeout", type=float, default=900.0)
    ap.add_argument("--idle", type=float, default=10.0,
                    help="push 模式下「多久没有新推送就认为分析结束」")
    ap.add_argument("--first-timeout", type=float, default=300.0,
                    help="push 模式下等「第一条推送」的上限；超时才判定为无诊断")
    ap.add_argument("--mode", choices=["push", "request"], default="push",
                    help="push=只认服务器推送（等价 flutter analyze）；"
                         "request=逐文件 getErrors（会多报被 exclude 的文件）")
    ap.add_argument("-v", "--verbose", action="store_true")
    a = ap.parse_args()

    sdk = find_sdk(a.sdk)
    if not sdk:
        print("找不到 Dart SDK（用 --sdk 指定）")
        return 2

    target = os.path.abspath(a.path)
    if not os.path.isdir(target):
        print("目录不存在: %s" % target)
        return 2

    print("=" * 72)
    print("Dart analysis_server 直驱（替代 flutter analyze / dart analyze）")
    print("  SDK     : %s" % sdk)
    print("  目标    : %s" % target)
    print("=" * 72)

    srv = Server(sdk, cwd=target, verbose=a.verbose)
    t0 = time.time()
    try:
        rid = srv.send("analysis.setAnalysisRoots",
                       {"included": [target], "excluded": []})
        r = srv.wait(rid, 60)
        if r is None:
            print("setAnalysisRoots 无响应（服务器可能没起来）")
            return 2
        if "error" in r:
            print("setAnalysisRoots 失败: %s" % r["error"])
            return 2

        srv.send("analysis.setSubscriptions", {"subscriptions": ["ERRORS"]})
        time.sleep(1.0)

        if a.mode == "push":
            # 忠实复刻 `flutter analyze`：只认服务器主动推送的 analysis.errors。
            # （逐文件 getErrors 的应答在某些情况下会漏掉 uri_does_not_exist，
            #   实测两者结果不同，所以默认用这条路径。）
            #
            # 结束判定 = 「推送静默了多久」。⚠️ idle 必须以**最后一次推送的时刻**
            # 为基准，绝不能以「循环上一轮」为基准 —— 那样 idle 恒等于一次 sleep
            # 的长度，早退条件永不成立，每个工程都空转到 --timeout（实测踩过：
            # 明明 8 秒就分析完，却干等了 15 分钟）。
            print("模式：push（只认服务器推送，等价于 flutter analyze 的口径）")
            seen_files = set()
            t_sub = time.time()
            last = t_sub
            deadline = t_sub + a.timeout
            first = a.first_timeout if a.first_timeout > 0 else a.timeout
            while time.time() < deadline:
                if srv.proc.poll() is not None:
                    print("⚠️ 分析服务器已退出（rc=%s），按现有推送结果收尾"
                          % srv.proc.returncode)
                    break
                with srv.lock:
                    cur = set(srv.errors_by_file)
                    n_ev = srv.errors_events
                    push_at = srv.last_push_at
                    total = sum(len(v) for v in srv.errors_by_file.values())
                if push_at > last:
                    last = push_at
                    seen_files = cur
                    if not a.quiet_files:
                        print("  ...已推送 %d 个文件 / %d 条诊断"
                              % (len(seen_files), total))
                if n_ev == 0:
                    # 一条推送都还没来：工程里可能真的没有 .dart 文件，
                    # 也可能第一次分析还没跑完。给 first_timeout 兜底，
                    # 别把「还在分析」误判成「干净」。
                    if time.time() - t_sub >= first:
                        print("⚠️ %.0fs 内没有任何推送，按「无 dart 文件 / 无诊断」处理"
                              % first)
                        break
                elif time.time() - last >= a.idle:
                    break
                time.sleep(0.1)
            err_files = sum(1 for v in srv.errors_by_file.values() if v)
            print("推送结束：%d 个文件被分析过（其中 %d 个带诊断），"
                  "共 %d 条（idle %.0fs，用时 %.1fs）"
                  % (len(srv.errors_by_file), err_files, total,
                     a.idle, time.time() - t0))
        else:
            # 自己去枚举磁盘上的 dart 文件，逐文件 getErrors。
            # 覆盖确定，但注意：分析服务器对「显式请求」的文件会照算，
            # 即使该文件被 analyzer.exclude 排除 —— 所以它会比 flutter analyze 多报。
            files = []
            for dirpath, dirs, names in os.walk(target):
                dirs[:] = [d for d in dirs if d not in SKIP_DIR_PARTS]
                for nm in names:
                    if nm.endswith(".dart"):
                        files.append(os.path.join(dirpath, nm))
            files.sort()
            print("模式：request（逐文件 getErrors）—— 磁盘上 %d 个 dart 文件" % len(files))

            pending = {}
            for i, f in enumerate(files, 1):
                pending[srv.send("analysis.getErrors", {"file": f})] = f
                if i % 100 == 0:
                    if not a.quiet_files:
                        print("  ...已提交 %d/%d" % (i, len(files)))
                    time.sleep(0.05)

            n = 0
            deadline = time.time() + a.timeout
            while pending and time.time() < deadline:
                if srv.proc.poll() is not None:
                    print("⚠️ 分析服务器已退出（rc=%s），剩余 %d 个文件拿不到结果"
                          % (srv.proc.returncode, len(pending)))
                    break
                with srv.lock:
                    ready = [k for k in pending if k in srv.responses]
                    got = [(k, pending.pop(k), srv.responses.pop(k)) for k in ready]
                if not got:
                    time.sleep(0.03)
                    continue
                for _k, f, resp in got:
                    if "error" in resp:
                        srv.not_analyzed[f] = resp["error"].get("message", "?")
                        continue
                    srv.errors_by_file[f] = (resp.get("result") or {}).get("errors") or []
                    n += 1
                if not a.quiet_files and n and n % 100 == 0:
                    print("  ...已取 %d/%d" % (n, len(files)))

            if pending:
                print("⚠️ 超时：还有 %d 个文件没取到结果" % len(pending))

        # 汇总
        rows = []
        counts = {"ERROR": 0, "WARNING": 0, "INFO": 0}
        for f, errs in sorted(srv.errors_by_file.items()):
            for e in errs:
                sev = e.get("severity", "INFO")
                counts[sev] = counts.get(sev, 0) + 1
                loc = e.get("location") or {}
                rows.append({
                    "file": uri_to_path(loc.get("file") or f),
                    "line": loc.get("startLine", 0),
                    "col": loc.get("startColumn", 0),
                    "severity": sev,
                    "code": e.get("code", ""),
                    "message": (e.get("message") or "").replace("\n", " "),
                })

        rows.sort(key=lambda r: (SEV_ORDER.get(r["severity"], 9),
                                 r["file"], r["line"], r["col"]))

        if srv.not_analyzed:
            print()
            print("被分析服务器拒之门外的文件 %d 个（= 被 analyzer.exclude 排除，"
                  "或不在分析根内）：" % len(srv.not_analyzed))
            shown = {}
            for f, why in sorted(srv.not_analyzed.items()):
                rel = os.path.relpath(f, target).replace(os.sep, "/")
                top = rel.split("/")[0] + "/" + (rel.split("/")[1] if "/" in rel else "")
                shown.setdefault(top, []).append(rel)
            for top, lst in list(shown.items())[:12]:
                print("   %-42s %d 个文件   例: %s" % (top, len(lst), lst[0]))
            if len(shown) > 12:
                print("   ...（还有 %d 组）" % (len(shown) - 12))

        print()
        if rows:
            print("诊断明细（按严重度排序）：")
            for r in rows:
                rel = os.path.relpath(r["file"], target).replace(os.sep, "/")
                print("  %-7s %s:%s:%s  %s  [%s]"
                      % (r["severity"], rel, r["line"], r["col"], r["message"], r["code"]))
        else:
            print("没有任何诊断 ✓")

        print()
        print("=" * 72)
        print("统计：ERROR=%d  WARNING=%d  INFO=%d   用时 %.1fs"
              % (counts["ERROR"], counts["WARNING"], counts["INFO"], time.time() - t0))
        print("=" * 72)

        # ⚠️ 已知口径差异（2026-10-08 实测对账）：
        # analysis_server 的 analysis.errors 会带上 `todo` 规则（// TODO 注释）的诊断，
        # 而 `flutter analyze` / `dart analyze` **不显示**这一类。
        # flutter_client 实测：本工具 75 条 vs flutter 70 条，差额恰好 = todo 的 5 条，
        # warning（9）逐条一致、error 均为 0。⇒ 对账时先扣掉 todo 再看。
        n_todo = sum(1 for r in rows if r["code"] == "todo")
        if n_todo:
            print("注：其中 %d 条属 `todo` 规则（// TODO 注释）。`flutter analyze` 不显示这类诊断，"
                  % n_todo)
            print("    扣掉后为 %d 条 —— 与 flutter analyze 对齐。这是口径差异，不是误报。"
                  % (len(rows) - n_todo))
            print("    ⇢ 速查 §9.4")
            print()

        if a.json:
            with open(a.json, "w", encoding="utf-8") as fh:
                json.dump({"mode": a.mode,
                           "analyzedFiles": srv.analyzed_files or [],
                           "withDiagnostics": sorted(srv.errors_by_file),
                           "notAnalyzed": srv.not_analyzed,
                           "diagnostics": rows},
                          fh, ensure_ascii=False, indent=1)
            print("原始诊断已写入 %s" % a.json)

        if counts["ERROR"]:
            return 1
        if a.fatal_warnings and counts["WARNING"]:
            return 1
        return 0
    finally:
        srv.close()


if __name__ == "__main__":
    sys.exit(main())
