#!/usr/bin/env python
"""设计文档相对链接可达性检查（供自动评级与 CI 使用）。

用法：python tools/check_docs_links.py
输出：相对链接总数；若有不可达项则列出并返回非零退出码。
"""
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")


def main():
    files = []
    for dirpath, _dirnames, filenames in os.walk(DOCS):
        for name in filenames:
            if name.endswith(".md"):
                files.append(os.path.join(dirpath, name))

    broken = []
    total = 0
    for path in sorted(files):
        with io.open(path, "r", encoding="utf-8") as handle:
            text = handle.read()
        for match in LINK_RE.finditer(text):
            target = match.group(1).strip()
            if target.startswith(("http://", "https://", "mailto:")):
                continue
            path_part = target.split("#")[0]
            if not path_part:
                continue
            total += 1
            resolved = os.path.normpath(os.path.join(os.path.dirname(path), path_part))
            if not os.path.exists(resolved):
                broken.append((os.path.relpath(path, ROOT), target))

    print("markdown files:", len(files))
    print("relative links checked:", total)
    if broken:
        print("BROKEN (%d):" % len(broken))
        for rel, target in broken:
            print("  %s -> %s" % (rel, target))
        return 1
    print("BROKEN: none")
    return 0


if __name__ == "__main__":
    sys.exit(main())