#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从 GNasCab 官方资源清单下载开发环境所需的运行时资源。

清单里每条的 path 是「相对于应用根目录」的路径，例如
    onnx_models/faces/insightFace/model.onnx
    libs/rclone/win/x64/rclone.exe
开发环境根目录 = electron_server/（config.getRootPath() 在未打包时返回 src/../../）
所以落地位置 = G:/work/nascab/electron_server/<path>

用法：
    python fetch_nascab_assets.py --manifest <url|本地文件> --root <应用根目录> \
        [--bundle onnx_models.faces ...] [--all-win-x64]
"""
import argparse
import hashlib
import json
import os
import sys
import urllib.request

CHUNK = 1 << 20  # 1 MiB


def human(n):
    for unit in ("B", "KiB", "MiB", "GiB"):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TiB"


def load_manifest(src):
    if os.path.exists(src):
        with open(src, "r", encoding="utf-8") as f:
            return json.load(f)
    with urllib.request.urlopen(src, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(CHUNK)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def file_ok(path, size, sha):
    if not os.path.isfile(path):
        return False
    if size and os.path.getsize(path) != size:
        return False
    if sha:
        return sha256_file(path) == sha.lower()
    return True


def download(url, dest, size, sha):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    part = dest + ".partial"
    got = 0
    with urllib.request.urlopen(url, timeout=120) as r, open(part, "wb") as f:
        total = int(r.headers.get("Content-Length") or 0)
        while True:
            chunk = r.read(CHUNK)
            if not chunk:
                break
            f.write(chunk)
            got += len(chunk)
            if total:
                pct = got * 100 // total
                sys.stdout.write(f"\r    {pct:3d}%  {human(got)} / {human(total)}   ")
                sys.stdout.flush()
    sys.stdout.write("\n")
    if size and os.path.getsize(part) != size:
        os.remove(part)
        raise RuntimeError(f"size mismatch: expected {size}, got {os.path.getsize(part)}")
    if sha and sha256_file(part) != sha.lower():
        os.remove(part)
        raise RuntimeError("sha256 mismatch")
    os.replace(part, dest)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--root", required=True, help="应用根目录（electron_server 的绝对路径）")
    ap.add_argument("--bundle", action="append", default=[])
    ap.add_argument("--all-win-x64", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    m = load_manifest(args.manifest)
    base = str(m.get("baseUrl", "")).rstrip("/")
    bundles = m["bundles"]

    targets = list(args.bundle)
    if args.all_win_x64:
        targets += [
            b for b in bundles
            if b.endswith(".win.x64") or b.startswith("onnx_models.")
        ]
    # 去重且保持顺序
    seen, ordered = set(), []
    for t in targets:
        if t not in seen:
            seen.add(t)
            ordered.append(t)

    if not ordered:
        print("没有指定要下载的 bundle。可用：")
        for b in bundles:
            print("  ", b)
        return 1

    grand = 0
    for bid in ordered:
        b = bundles.get(bid)
        if b is None:
            print(f"!! 清单里没有 bundle: {bid}")
            continue
        files = b.get("files", [])
        todo = []
        for fe in files:
            rel = str(fe["path"]).replace("\\", "/").lstrip("/")
            dest = os.path.join(args.root, *rel.split("/"))
            if file_ok(dest, fe.get("size"), fe.get("sha256")):
                print(f"  [跳过] 已存在且校验通过: {rel}")
                continue
            todo.append((rel, dest, fe))
        size = sum(f.get("size", 0) for _, _, f in todo)
        print(f"[{bid}] 待下载 {len(todo)}/{len(files)} 个文件，共 {human(size)}")
        if args.dry_run:
            for rel, _, fe in todo:
                print(f"    - {rel}  ({human(fe.get('size', 0))})")
            continue
        for i, (rel, dest, fe) in enumerate(todo, 1):
            url = fe.get("url") or f"{base}/{rel}"
            print(f"  ({i}/{len(todo)}) {rel}")
            download(url, dest, fe.get("size"), fe.get("sha256"))
            print(f"    ok -> {dest}")
            grand += fe.get("size", 0)

    if not args.dry_run:
        print(f"\n完成，本次实际下载 {human(grand)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
