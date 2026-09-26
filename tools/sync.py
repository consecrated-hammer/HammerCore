#!/usr/bin/env python3
"""Vendor HammerCore into an addon, pinned to the current commit.

Usage: sync.py <addon-dir> [--allow-dirty]

Copies src/ to <addon>/Libs/HammerCore/ and the test harness to
<addon>/tests/hammercore/, then records the version and commit in
Libs/HammerCore/VERSION.  check.py later proves the copy matches that commit.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def git(*args: str) -> str:
    return subprocess.run(["git", "-C", str(ROOT), *args], check=True,
                          capture_output=True, text=True).stdout.strip()


def version() -> str:
    match = re.search(r'HC\.VERSION = "([^"]+)"', (ROOT / "src" / "Core.lua").read_text(encoding="utf-8"))
    if not match:
        raise SystemExit("src/Core.lua has no HC.VERSION")
    return match.group(1)


def replace_tree(source: Path, destination: Path) -> None:
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("addon", type=Path)
    parser.add_argument("--allow-dirty", action="store_true",
                        help="vendor uncommitted work (the pin will not verify)")
    args = parser.parse_args()
    addon = args.addon.resolve()
    if not (addon / ".git").exists():
        raise SystemExit(f"{addon} is not an addon repository")
    dirty = git("status", "--porcelain", "--", "src", "tests/wow.lua")
    if dirty and not args.allow_dirty:
        raise SystemExit("HammerCore src/ has uncommitted changes; commit first so the pin is real")
    commit = git("rev-parse", "HEAD")
    library = addon / "Libs" / "HammerCore"
    replace_tree(ROOT / "src", library)
    (library / "VERSION").write_text(f"version={version()}\ncommit={commit}\n", encoding="utf-8")
    harness = addon / "tests" / "hammercore"
    harness.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "tests" / "wow.lua", harness / "wow.lua")
    print(f"Vendored HammerCore {version()} ({commit[:7]}) into {library}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
