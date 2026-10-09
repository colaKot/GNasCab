#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""命名管道只读打开自检 —— 诊断「Dart 建不了子进程」的真根因（2026-10-08 定位）。

背景
----
本机 `flutter` / `dart analyze` 全部跑不起来，报：
    CreateFile failed 231
    ProcessException: 所有的管道范例都在使用中。 (process_win.cc:693)
231 = ERROR_PIPE_BUSY（所有的管道范例都在使用中）。

根因不在 Dart，也不在沙箱，而在**本机 OS 层**：客户端以「只读」权限
（`GENERIC_READ`）打开命名管道时，`CreateFileW` 必定返回 231。

为什么这会卡死编译
------------------
Dart 的 `runtime/bin/process_win.cc::CreateProcessPipe()` 在 `kInheritRead`
分支里就是这么干的（源码原文）：

    handles[kWriteHandle] = CreateNamedPipeW(pipe_name,
        PIPE_ACCESS_OUTBOUND | FILE_FLAG_OVERLAPPED, PIPE_TYPE_BYTE | PIPE_WAIT,
        1, 1024, 1024, 0, nullptr);
    handles[kReadHandle] = CreateFileW(pipe_name, GENERIC_READ, 0, &inherit_handle,
        OPEN_EXISTING, FILE_READ_ATTRIBUTES | FILE_FLAG_OVERLAPPED, nullptr);
    if (handles[kReadHandle] == INVALID_HANDLE_VALUE) {
      Syslog::PrintErr("CreateFile failed %d (%s)\\n", ...);   // ← 就是这里
      return false;
    }

而 `Process.start` 建三条管道时用的是**短路或**，且 stdin 排第一：

    if (!CreateProcessPipe(stdin_handles_,  pipe_names[0], kInheritRead) ||
        !CreateProcessPipe(stdout_handles_, pipe_names[1], kInheritWrite) ||
        !CreateProcessPipe(stderr_handles_, pipe_names[2], kInheritWrite)) { ... }

⇒ 第一条（stdin / kInheritRead）就必然失败并短路。
⇒ Dart 的**任何**要管道的子进程创建（`Process.run/runSync/start`）当场抛
   ProcessException。`inheritStdio` 不用管道 ⇒ 反而正常（这就是为什么
   `tool/dart_analyze.py` 能在本机跑：它自己不需要建子进程）。

用法
----
    python tool/check_named_pipe.py

退出码 0 = 正常；1 = 复现了本机的缺陷（只读打开 231）。
请在**你自己的 cmd**（不在 WorkBuddy/IDE 里）也跑一次，用于判断是不是
WorkBuddy 的宿主环境造成的。
"""
import ctypes
import ctypes.wintypes as w
import sys
import time

PIPE_ACCESS_INBOUND = 0x1
PIPE_ACCESS_OUTBOUND = 0x2
PIPE_ACCESS_DUPLEX = 0x3
GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
OPEN_EXISTING = 3
INVALID = ctypes.c_void_p(-1).value

k32 = ctypes.WinDLL("kernel32", use_last_error=True)


class SA(ctypes.Structure):
    _fields_ = [("nLength", w.DWORD), ("lpSecurityDescriptor", ctypes.c_void_p),
                ("bInheritHandle", w.BOOL)]


k32.CreateNamedPipeW.restype = w.HANDLE
k32.CreateNamedPipeW.argtypes = [w.LPCWSTR, w.DWORD, w.DWORD, w.DWORD, w.DWORD,
                                 w.DWORD, w.DWORD, ctypes.POINTER(SA)]
k32.CreateFileW.restype = w.HANDLE
k32.CreateFileW.argtypes = [w.LPCWSTR, w.DWORD, w.DWORD, ctypes.POINTER(SA),
                            w.DWORD, w.DWORD, w.HANDLE]
k32.CloseHandle.argtypes = [w.HANDLE]


def _sa():
    s = SA()
    s.nLength = ctypes.sizeof(SA)
    s.bInheritHandle = True
    s.lpSecurityDescriptor = None
    return s


_n = [0]


def _probe(label, open_mode, cf_access):
    """建一条命名管道，再用指定权限打开，返回 (成功?, 错误码)。"""
    _n[0] += 1
    sa = _sa()
    name = r"\\.\Pipe\nascab_selfcheck_%x_%d" % (int(time.time() * 1e6), _n[0])
    hw = k32.CreateNamedPipeW(name, open_mode, 0, 1, 1024, 1024, 0,
                              ctypes.byref(sa))
    if hw == INVALID:
        return None, ctypes.get_last_error()
    ctypes.set_last_error(0)
    hr = k32.CreateFileW(name, cf_access, 0, ctypes.byref(sa), OPEN_EXISTING, 0,
                         None)
    err = ctypes.get_last_error()
    if hr != INVALID:
        k32.CloseHandle(hr)
    k32.CloseHandle(hw)
    return hr != INVALID, err


def main():
    print("=" * 74)
    print("命名管道只读打开自检（解释 Dart「所有的管道范例都在使用中」）")
    print("=" * 74)

    cases = [
        ("DUPLEX   + 客户端只读   ← Dart 的 stdin 管道形状", PIPE_ACCESS_DUPLEX,
         GENERIC_READ),
        ("DUPLEX   + 客户端读写   ← 对照", PIPE_ACCESS_DUPLEX,
         GENERIC_READ | GENERIC_WRITE),
        ("INBOUND  + 客户端只写   ← Dart 的 stdout 管道形状", PIPE_ACCESS_INBOUND,
         GENERIC_WRITE),
        ("OUTBOUND + 客户端只读   ← Dart 的 stdin 管道形状", PIPE_ACCESS_OUTBOUND,
         GENERIC_READ),
    ]

    bad = 0
    for label, mode, access in cases:
        ok, err = _probe(label, mode, access)
        if ok is None:
            print("  %-52s ⚠️  CreateNamedPipe 就失败了 err=%d" % (label, err))
            continue
        if ok:
            print("  %-52s ✅ 成功" % label)
        else:
            who = {231: "ERROR_PIPE_BUSY",
                   121: "ERROR_SEM_TIMEOUT",
                   5: "ERROR_ACCESS_DENIED"}.get(err, "")
            print("  %-52s ❌ err=%d %s" % (label, err, who))
            if err == 231:
                bad += 1

    print("-" * 74)
    if bad:
        print("结论：当前进程树里存在该缺陷 —— 命名管道「只读」打开返回 231。")
        print("      Dart 的 CreateProcessPipe(kInheritRead) 第一步就是这个，")
        print("      所以 flutter / dart analyze 一律在建子进程时崩。")
        print()
        print("⭐ 2026-10-08 已确认边界：**只在 WorkBuddy 的进程树里**。")
        print("   铁柱在自己的普通 cmd 里跑 tool/flutter-check.bat → all steps passed，")
        print("   四个 build bundle 全 [OK] ⇒ 普通 cmd 里 Dart 建子进程完全正常。")
        print()
        print("   ⇒ 不是 Dart 缺陷、不是系统级、**不用去关安全软件**、关沙箱也一样。")
        print("   ⇒ 处理办法：flutter pub get / analyze / build 一律在普通 cmd 里跑。")
        print("      本 Agent 侧要静态诊断，用 python tool/dart_analyze.py <工程>。")
        return 1
    print("结论：命名管道只读打开正常 ✓ —— 那么 Dart 建子进程不该失败，")
    print("      请把本脚本的输出发回来，需要重新定位。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
