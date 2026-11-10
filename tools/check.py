#!/usr/bin/env python3
"""Fail if an addon's vendored HammerCore differs from its pinned commit.

Usage: check.py <addon-dir>

Also fails an addon that turns on HammerCore flight times (`flights = true`,
or a `flights = { ... }` table without `estimates = false`) without declaring LibTaxiData in every TOC (`## Dependencies` or
`## OptionalDeps`) and in .pkgmeta (`required-dependencies` or
`optional-dependencies`): HammerCore is vendored, so only the addon itself
can tell the game and the CurseForge app about the library.

Run from a HammerCore checkout that contains the pinned commit.  Addon CI
clones HammerCore and runs this, so a hand edit to Libs/HammerCore cannot
reach a release.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def pinned_file(commit: str, path: str) -> bytes | None:
    result = subprocess.run(["git", "-C", str(ROOT), "show", f"{commit}:{path}"], capture_output=True)
    return result.stdout if result.returncode == 0 else None


FLIGHTS = re.compile(r"\bflights\s*=\s*(?:true\b|(\{[^{}]*\}))")
NO_ESTIMATES = re.compile(r"\bestimates\s*=\s*false\b")
COMMENT = re.compile(r"--[^\n]*")


def needs_library(source: str) -> bool:
    """Whether Lua source turns on flight times: `flights = true`, or a
    `flights = { ... }` table that doesn't say `estimates = false`."""
    for match in FLIGHTS.finditer(COMMENT.sub("", source)):
        table = match.group(1)
        if table is None or not NO_ESTIMATES.search(table):
            return True
    return False


def uses_flights(addon: Path) -> bool:
    for path in addon.rglob("*.lua"):
        parts = path.relative_to(addon).parts
        if parts[0] in ("Libs", "tests", ".git"):
            continue
        if needs_library(path.read_text(encoding="utf-8", errors="ignore")):
            return True
    return False


def pkgmeta_dependencies(text: str) -> set[str]:
    """Names under required-dependencies or optional-dependencies."""
    names: set[str] = set()
    inside = False
    for line in text.splitlines():
        if re.match(r"^(?:required|optional)-dependencies:\s*$", line):
            inside = True
            continue
        if inside:
            item = re.match(r"^\s+-\s*(\S+)", line)
            if item:
                names.add(item.group(1).lower())
            elif line.strip() and not line.startswith((" ", "\t", "#")):
                inside = False
    return names


def flight_problems(addon: Path) -> list[str]:
    """The LibTaxiData declarations a flights addon is missing."""
    if not uses_flights(addon):
        return []
    problems = []
    for toc in sorted(addon.glob("*.toc")):
        listed: set[str] = set()
        for line in toc.read_text(encoding="utf-8", errors="ignore").splitlines():
            match = re.match(r"^##\s*(?:Dependencies|RequiredDeps|OptionalDeps)\s*:\s*(.*)$", line)
            if match:
                listed |= {name.strip().lower() for name in match.group(1).split(",")}
        if "libtaxidata" not in listed:
            problems.append(f"{toc.name} uses flights but doesn't list LibTaxiData in ## Dependencies or ## OptionalDeps")
    pkgmeta = addon / ".pkgmeta"
    text = pkgmeta.read_text(encoding="utf-8") if pkgmeta.is_file() else ""
    if "libtaxidata" not in pkgmeta_dependencies(text):
        problems.append(".pkgmeta uses flights but doesn't list libtaxidata as a dependency")
    return problems


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
    # Recursive: src/ has subfolders such as Textures.  Paths are relative
    # to src/ and use forward slashes, matching git's own listing.
    listing = subprocess.run(["git", "-C", str(ROOT), "ls-tree", "-r", "-z", "--name-only", commit, "src/"],
                             capture_output=True, text=True)
    if listing.returncode != 0:
        print(f"{addon.name}: pinned commit {commit} is not in this HammerCore checkout")
        return 1
    problems = []
    expected = {name[len("src/"):] for name in listing.stdout.split("\0") if name.startswith("src/")}
    for name in sorted(expected):
        vendored = library / name
        if not vendored.is_file():
            problems.append(f"missing {name}")
        elif vendored.read_bytes() != pinned_file(commit, f"src/{name}"):
            problems.append(f"modified {name}")
    for path in sorted(library.rglob("*")):
        if not path.is_file():
            continue
        name = path.relative_to(library).as_posix()
        if name != "VERSION" and name not in expected:
            problems.append(f"unexpected {name}")
    harness = addon / "tests" / "hammercore" / "wow.lua"
    if harness.is_file() and harness.read_bytes() != pinned_file(commit, "tests/wow.lua"):
        problems.append("modified tests/hammercore/wow.lua")
    dependencies = flight_problems(addon)
    if dependencies:
        print(f"{addon.name}: flights need LibTaxiData declared:")
        for problem in dependencies:
            print(f"  {problem}")
        if not problems:
            return 1
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
