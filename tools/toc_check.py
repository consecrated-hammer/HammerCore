#!/usr/bin/env python3
"""Fail if any TOC in an addon does not load exactly the addon's Lua files.

Usage: toc_check.py <addon-dir>

A Lua file counts as loaded when a TOC lists it directly or lists an XML
file whose <Script file="..."/> includes it (how Libs/HammerCore loads).
Files under tests/, tools/ and dot-directories are not runtime code.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path, PurePosixPath

SKIP = {"tests", "tools", "docs", "data", "media"}


def runtime_lua(addon: Path) -> set[str]:
    found = set()
    for path in addon.rglob("*.lua"):
        relative = path.relative_to(addon)
        if any(part.startswith(".") or part in SKIP for part in relative.parts):
            continue
        found.add(relative.as_posix())
    return found


def xml_scripts(addon: Path, xml: str, seen: set[str]) -> set[str]:
    if xml in seen:
        return set()
    seen.add(xml)
    path = addon / xml
    if not path.is_file():
        raise SystemExit(f"listed XML is missing: {xml}")
    base = PurePosixPath(xml).parent
    loaded = set()
    text = path.read_text(encoding="utf-8")
    for kind, name in re.findall(r'<(Script|Include)\s+file="([^"]+)"', text):
        child = (base / name.replace("\\", "/")).as_posix()
        if kind == "Script":
            loaded.add(child)
        else:
            loaded |= xml_scripts(addon, child, seen)
    return loaded


def toc_loaded(addon: Path, toc: Path) -> set[str]:
    loaded = set()
    for raw in toc.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        entry = line.replace("\\", "/")
        if entry.endswith(".lua"):
            loaded.add(entry)
        elif entry.endswith(".xml"):
            loaded |= xml_scripts(addon, entry, set())
    return loaded


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("addon", type=Path)
    args = parser.parse_args()
    addon = args.addon.resolve()
    on_disk = runtime_lua(addon)
    failed = False
    tocs = sorted(addon.glob("*.toc"))
    if not tocs:
        print(f"{addon.name}: no TOC files")
        return 1
    for toc in tocs:
        loaded = toc_loaded(addon, toc)
        missing, extra = sorted(on_disk - loaded), sorted(loaded - on_disk)
        for name in missing:
            print(f"{toc.name}: does not load {name}")
        for name in extra:
            print(f"{toc.name}: lists missing file {name}")
        failed = failed or bool(missing or extra)
        if not missing and not extra:
            print(f"{toc.name}: loads all {len(loaded)} Lua files")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
