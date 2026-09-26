#!/usr/bin/env python3
"""Stage a runtime-only copy of an addon into the Syncthing client folders.

Usage: stage.py <addon-dir> [--client retail|forever|both] [--output DIR]

By default it stages every client the addon ships a TOC for.

Each client receives the whole runtime folder with every TOC, and the TOC
that client loads is stamped with an incrementing -devN version, so an
in-game `/<cmd> version` identifies exactly which build is loaded.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import tempfile
from pathlib import Path

CLIENTS = {
    "retail": (Path("/mnt/backup/syncthing/kevin/wow-interface/AddOns"), "{name}.toc"),
    "forever": (Path("/mnt/backup/syncthing/kevin/wow-forever-beta-interface/AddOns"), "{name}_Camelot.toc"),
}
RUNTIME_SUFFIXES = {".lua", ".xml", ".tga", ".blp", ".ogg", ".mp3", ".wav", ".ttf"}
EXCLUDED_PARTS = {".git", ".github", ".scratch", "tests", "tools", "docs", "data", "media", "__pycache__"}


def copy_runtime(source: Path, destination: Path) -> None:
    for path in source.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(source)
        if any(part.startswith(".") or part in EXCLUDED_PARTS for part in relative.parts):
            continue
        if path.suffix.lower() not in RUNTIME_SUFFIXES:
            continue
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    for toc in source.glob("*.toc"):
        shutil.copy2(toc, destination / toc.name)


def dev_version(toc: Path, name: str, roots: list[Path]) -> str:
    """The next -devN, one above the highest seen in any client.

    Every TOC of the installed copy and of a set-aside `.Name.previous` copy
    counts, in every client root, so an interrupted swap never resets the
    number and both clients carry the same version.
    """
    match = re.search(r"^## Version:\s*(.+?)\s*$", toc.read_text(encoding="utf-8"), re.MULTILINE)
    if not match:
        raise SystemExit(f"TOC has no Version metadata: {toc}")
    base = re.sub(r"-dev-?\d+$", "", match.group(1))
    highest = 0
    pattern = re.compile(r"^## Version:\s*" + re.escape(base) + r"-dev-?(\d+)\s*$", re.MULTILINE)
    for root in roots:
        for folder in (root / name, root / f".{name}.previous"):
            if not folder.is_dir():
                continue
            for installed in folder.glob("*.toc"):
                for found in pattern.findall(installed.read_text(encoding="utf-8", errors="replace")):
                    highest = max(highest, int(found))
    return f"{base}-dev{highest + 1}"


def stage(source: Path, name: str, output: Path, toc_name: str, version: str) -> None:
    selected = source / toc_name
    if not selected.is_file():
        raise SystemExit(f"missing {toc_name} in {source}")
    output = output.resolve()
    if output == source or source in output.parents:
        raise SystemExit("output must be outside the source repository")
    destination = output / name
    output.mkdir(parents=True, exist_ok=True)
    stage_root = Path(tempfile.mkdtemp(prefix=f".{name}.stage-", dir=output))
    staged = stage_root / name
    backup = output / f".{name}.previous"
    try:
        staged.mkdir()
        copy_runtime(source, staged)
        staged_toc = staged / toc_name
        staged_toc.write_text(re.sub(r"^## Version:\s*.+?$", f"## Version: {version}",
                                     staged_toc.read_text(encoding="utf-8"), flags=re.MULTILINE),
                              encoding="utf-8")
        if backup.exists():
            shutil.rmtree(backup)
        if destination.exists():
            os.replace(destination, backup)
        try:
            os.replace(staged, destination)
        except BaseException:
            if backup.exists() and not destination.exists():
                os.replace(backup, destination)
            raise
        if backup.exists():
            shutil.rmtree(backup)
    finally:
        if stage_root.exists():
            shutil.rmtree(stage_root)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("addon", type=Path)
    parser.add_argument("--client", choices=["retail", "forever", "both"],
                        help="default: every client the addon has a TOC for")
    parser.add_argument("--output", type=Path, help="stage into DIR instead of the client folder")
    args = parser.parse_args()
    source = args.addon.resolve()
    name = source.name
    if args.client in (None, "both"):
        clients = [c for c in ("retail", "forever") if (source / CLIENTS[c][1].format(name=name)).is_file()]
        if args.client == "both" and len(clients) < 2:
            raise SystemExit(f"{name} does not ship TOCs for both clients")
        if not clients:
            raise SystemExit(f"{name} has no client TOC")
    else:
        clients = [args.client]
    roots = [args.output] if args.output else [CLIENTS[c][0] for c in ("retail", "forever")]
    version = dev_version(source / CLIENTS[clients[0]][1].format(name=name), name, roots)
    for client in clients:
        folder, toc = CLIENTS[client]
        # Never create a client folder: a missing one means the Syncthing
        # share is not mounted, and staging would write into the bare mount point.
        if not args.output and not folder.is_dir():
            raise SystemExit(f"{folder} is missing; is the Syncthing share mounted?")
        stage(source, name, args.output or folder, toc.format(name=name), version)
        print(f"Staged {name} {version} for {client} at {(args.output or folder) / name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
