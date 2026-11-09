#!/usr/bin/env python3
"""Fail if a released version has no What's new highlights.

Usage: whatsnew_check.py <addon-dir> [--version X.Y.Z]

Every CurseForge release gets a What's new entry, fixes included (Kevin,
2026-11-09).  This checks every dated CHANGELOG.md release from the addon's
first What's new entry onwards, plus --version when given (the release
workflow passes the tag, so a release can't ship without its entry).
Releases from before the addon adopted What's new are not required: entries
marked `history = true` (highlights written after the fact) don't move the
starting point back, so back-filling a few milestones never demands an
entry for every old patch.

Entries are found by their shape in the addon's own Lua, outside Libs/ and
tests/:  { version = "1.8.0", date = "...", history = true, items = { ... } }
(date and history are optional).  -beta and -devN suffixes
count as their base version, as the window itself does.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

HEADING = re.compile(r"^## \[v?([0-9][^\]]*)\] - \d{4}-\d{2}-\d{2}\s*$", re.MULTILINE)
ENTRY = re.compile(r"""\{\s*version\s*=\s*["']([^"']+)["']\s*,((?:\s*\w+\s*=\s*[^,{}]+,)*)\s*items\s*=""")
HISTORY = re.compile(r"\bhistory\s*=\s*true\b")
SKIP = {"Libs", "tests", ".git", ".scratch", "tools", "data", "docs"}


def base(version: str) -> tuple[int, ...] | None:
    match = re.match(r"v?(\d+(?:\.\d+)*)", version.strip())
    if not match:
        return None
    parts = [int(part) for part in match.group(1).split(".")]
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts)


def text(version: tuple[int, ...]) -> str:
    return ".".join(str(part) for part in version)


def entries(addon: Path) -> dict[tuple[int, ...], bool]:
    """Every entry's base version -> whether it is a back-filled history entry."""
    found: dict[tuple[int, ...], bool] = {}
    for path in addon.rglob("*.lua"):
        if any(part in SKIP for part in path.relative_to(addon).parts):
            continue
        for version, fields in ENTRY.findall(path.read_text(encoding="utf-8", errors="replace")):
            parsed = base(version)
            if parsed:
                found[parsed] = found.get(parsed, True) and bool(HISTORY.search(fields))
    return found


def releases(addon: Path) -> list[tuple[int, ...]]:
    changelog = addon / "CHANGELOG.md"
    if not changelog.is_file():
        return []
    found = []
    for version in HEADING.findall(changelog.read_text(encoding="utf-8")):
        parsed = base(version)
        if parsed and parsed not in found:
            found.append(parsed)
    return found


def check(addon: Path, version: str | None = None) -> list[str]:
    have = entries(addon)
    if not have:
        return [f"{addon.name}: no What's new highlights. Vendor a HammerCore with WhatsNew.lua, "
                "pass spec.whatsNew to HC:Init and add an entry for this release."]
    current = [version for version, history in have.items() if not history]
    if not current:
        return [f"{addon.name}: every What's new entry is marked history; the latest release needs a normal entry"]
    first = min(current)
    required = [release for release in releases(addon) if release >= first]
    if version:
        tagged = base(version)
        if tagged is None:
            return [f"{addon.name}: can't read version {version!r}"]
        if tagged not in required:
            required.append(tagged)
    missing = sorted({release for release in required if release not in have}, reverse=True)
    return [f"{addon.name}: no What's new entry for {text(release)}" for release in missing]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("addon", type=Path)
    parser.add_argument("--version", help="the version being released (the tag, with or without v)")
    args = parser.parse_args()
    problems = check(args.addon.resolve(), args.version)
    for problem in problems:
        print(problem)
    if not problems:
        print(f"{args.addon.resolve().name}: What's new covers every release")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
