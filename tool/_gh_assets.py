#!/usr/bin/env python3
"""Print the asset names + download URLs of a GitHub release.

WebFetch kept coming back empty for the GitHub JSON API, so this does it from the
bridge's terminal (which has working network) instead.

Usage:
  python tool/_gh_assets.py wang-bin/mdk-sdk v0.39.0
  python tool/_gh_assets.py wang-bin/mdk-sdk latest --proxy http://127.0.0.1:21578
  python tool/_gh_assets.py wang-bin/mdk-sdk v0.39.0 --filter windows
"""

import argparse
import json
import urllib.error
import urllib.request


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("repo", help="owner/name")
    ap.add_argument("tag", help="tag name, or 'latest'")
    ap.add_argument("--proxy", default=None)
    ap.add_argument("--filter", default=None, help="only print assets containing this substring")
    ap.add_argument("--timeout", type=float, default=45.0)
    a = ap.parse_args()

    url = ("https://api.github.com/repos/%s/releases/latest" % a.repo
           if a.tag == "latest" else
           "https://api.github.com/repos/%s/releases/tags/%s" % (a.repo, a.tag))
    handlers = []
    if a.proxy:
        handlers.append(urllib.request.ProxyHandler({"http": a.proxy, "https": a.proxy}))
    req = urllib.request.Request(url)
    req.add_header("User-Agent", "gnascab-asset-probe")
    req.add_header("Accept", "application/vnd.github+json")
    try:
        with urllib.request.build_opener(*handlers).open(req, timeout=a.timeout) as r:
            data = json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        print("HTTPError %s %s" % (exc.code, exc.reason))
        return 1
    except Exception as exc:  # noqa: BLE001
        print("FAILED: %s: %s" % (type(exc).__name__, exc))
        return 1

    print("tag      : %s" % data.get("tag_name"))
    print("published: %s" % data.get("published_at"))
    assets = data.get("assets") or []
    print("assets   : %d" % len(assets))
    for asset in assets:
        name = asset.get("name", "")
        if a.filter and a.filter.lower() not in name.lower():
            continue
        print("  %-44s %9d  %s" % (name, asset.get("size", 0), asset.get("browser_download_url", "")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
