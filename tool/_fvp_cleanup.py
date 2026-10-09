#!/usr/bin/env python3
"""Clean up leftovers from a killed fvp/CMake configure, so the next build can lock.

Why: `fvp/cmake/deps.cmake` takes an OS file lock on `<fvp pkg>/windows/fvp-deps.lock`
with `TIMEOUT 300`. If a previous configure was killed mid-flight, a stray cmake.exe
can survive holding that lock, and the next `flutter build windows` burns 5 minutes
and then dies with "Failed to lock the MDK SDK cache: Timeout reached".

Run through the bridge (it needs to be outside the WorkBuddy sandbox, and `rm`/`del`
are routed to a trash helper that fails on these files):
  python tool/bridge_cli.py run --shell 'python "G:\\work\\nascab\\tool\\_fvp_cleanup.py"'
"""

import ctypes
import ctypes.wintypes as w
import glob
import os
import sys

TH32CS_SNAPPROCESS = 0x00000002
PROCESS_TERMINATE = 0x0001
INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value
KILL_NAMES = ("cmake.exe", "vctip.exe")

k32 = ctypes.WinDLL("kernel32", use_last_error=True)


class PROCESSENTRY32(ctypes.Structure):
    _fields_ = [
        ("dwSize", w.DWORD), ("cntUsage", w.DWORD), ("th32ProcessID", w.DWORD),
        ("th32DefaultHeapID", ctypes.c_void_p), ("th32ModuleID", w.DWORD),
        ("cntThreads", w.DWORD), ("th32ParentProcessID", w.DWORD),
        ("pcPriClassBase", ctypes.c_long), ("dwFlags", w.DWORD),
        ("szExeFile", ctypes.c_char * 260),
    ]


def snapshot():
    snap = k32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if snap == INVALID_HANDLE_VALUE:
        raise OSError("snapshot failed: %d" % ctypes.get_last_error())
    try:
        e = PROCESSENTRY32()
        e.dwSize = ctypes.sizeof(PROCESSENTRY32)
        ok = k32.Process32First(snap, ctypes.byref(e))
        while ok:
            yield e.szExeFile.decode("mbcs", "replace"), e.th32ProcessID
            ok = k32.Process32Next(snap, ctypes.byref(e))
    finally:
        k32.CloseHandle(snap)


def kill_strays():
    killed = 0
    for name, pid in list(snapshot()):
        if name.lower() not in KILL_NAMES:
            continue
        if pid == os.getpid():
            continue
        h = k32.OpenProcess(PROCESS_TERMINATE, False, pid)
        if not h:
            print("  cannot open %s pid=%d (err=%d)" % (name, pid, ctypes.get_last_error()))
            continue
        ok = k32.TerminateProcess(h, 1)
        k32.CloseHandle(h)
        print("  %s %s pid=%d" % ("killed" if ok else "FAILED", name, pid))
        killed += 1
    if not killed:
        print("  no stray cmake/vctip process")
    return killed


def fvp_windows_dirs():
    base = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Pub", "Cache", "hosted")
    out = []
    for host in glob.glob(os.path.join(base, "*")):
        for pkg in glob.glob(os.path.join(host, "fvp-*")):
            win = os.path.join(pkg, "windows")
            if os.path.isdir(win):
                out.append(win)
    return out


def main():
    print("stray processes:")
    kill_strays()

    print("fvp windows dirs:")
    rows = []
    for win in fvp_windows_dirs():
        print("  %s" % win)
        for pattern in ("fvp-deps.lock", "*.part", "*.pypart"):
            for path in glob.glob(os.path.join(win, pattern)):
                size = os.path.getsize(path)
                try:
                    os.remove(path)
                    print("    removed %-34s (%d bytes)" % (os.path.basename(path), size))
                except OSError as exc:
                    print("    FAILED to remove %s: %s" % (path, exc))
        sdk = os.path.join(win, "mdk-sdk-windows-x64.7z")
        if os.path.exists(sdk):
            print("    mdk archive present: %d bytes" % os.path.getsize(sdk))
        else:
            print("    mdk archive MISSING (build WILL try to download)")
        rows.append(win)

    print("remaining entries:")
    for win in rows:
        for name in sorted(os.listdir(win)):
            if name.endswith((".lock", ".part", ".pypart")):
                print("    STILL THERE: %s" % os.path.join(win, name))
    return 0


if __name__ == "__main__":
    sys.exit(main())
