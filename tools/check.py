#!/usr/bin/env python3
"""Fail if an addon's vendored HammerCore differs from its pinned commit.

Usage: check.py <addon-dir>

Run from a HammerCore checkout that contains the pinned commit.  Addon CI
clones HammerCore and runs this, so a hand edit to Libs/HammerCore cannot
reach a release.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def pinned_file(commit: str, path: str) -> bytes | None:
    result = subprocess.run(["git", "-C", str(ROOT), "show", f"{commit}:{path}"], capture_output=True)
    return result.stdout if result.returncode == 0 else None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("addon", type=Path)
    args = parser.parse_args()
    addon = args.addon.resolve()
    library = addon / "Libs" / "HammerCore"
    stamp = library / "VERSION"
    if not stamp.is_file():
        print(f"{addon.name}: no vendored HammerCore (missing {stamp})")
        return 1
    fields = dict(line.split("=", 1) for line in stamp.read_text(encoding="utf-8").split() if "=" in line)
    commit = fields.get("commit", "")
    listing = subprocess.run(["git", "-C", str(ROOT), "ls-tree", "--name-only", commit, "src/"],
                             capture_output=True, text=True)
    if listing.returncode != 0:
        print(f"{addon.name}: pinned commit {commit} is not in this HammerCore checkout")
        return 1
    problems = []
    expected = {Path(name).name for name in listing.stdout.split()}
    for name in sorted(expected):
        vendored = library / name
        if not vendored.is_file():
            problems.append(f"missing {name}")
        elif vendored.read_bytes() != pinned_file(commit, f"src/{name}"):
            problems.append(f"modified {name}")
    for path in library.iterdir():
        if path.name != "VERSION" and path.name not in expected:
            problems.append(f"unexpected {path.name}")
    harness = addon / "tests" / "hammercore" / "wow.lua"
    if harness.is_file() and harness.read_bytes() != pinned_file(commit, "tests/wow.lua"):
        problems.append("modified tests/hammercore/wow.lua")
    if problems:
        print(f"{addon.name}: vendored HammerCore differs from {commit[:7]}:")
        for problem in problems:
            print(f"  {problem}")
        print("Edit HammerCore itself, commit, then run tools/sync.py.")
        return 1
    print(f"{addon.name}: HammerCore {fields.get('version')} ({commit[:7]}) verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
