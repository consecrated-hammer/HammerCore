#!/usr/bin/env python3
"""Stage a runtime-only copy of an addon into the Syncthing client folders.

Usage: stage.py <addon-dir> [--client retail|forever|both] [--output DIR]

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


def dev_version(toc: Path, existing: Path) -> str:
    match = re.search(r"^## Version:\s*(.+?)\s*$", toc.read_text(encoding="utf-8"), re.MULTILINE)
    if not match:
        raise SystemExit(f"TOC has no Version metadata: {toc}")
    base = re.sub(r"-dev-?\d+$", "", match.group(1))
    number = 1
    if existing.is_file():
        prior = re.search(r"^## Version:\s*" + re.escape(base) + r"-dev-?(\d+)\s*$",
                          existing.read_text(encoding="utf-8", errors="replace"), re.MULTILINE)
        if prior:
            number = int(prior.group(1)) + 1
    return f"{base}-dev{number}"


def stage(source: Path, name: str, output: Path, toc_name: str) -> str:
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
        version = dev_version(selected, destination / toc_name)
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
    return version


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("addon", type=Path)
    parser.add_argument("--client", choices=["retail", "forever", "both"], default="both")
    parser.add_argument("--output", type=Path, help="stage into DIR instead of the client folder")
    args = parser.parse_args()
    source = args.addon.resolve()
    name = source.name
    clients = ["retail", "forever"] if args.client == "both" else [args.client]
    for client in clients:
        folder, toc = CLIENTS[client]
        version = stage(source, name, args.output or folder, toc.format(name=name))
        print(f"Staged {name} {version} for {client} at {(args.output or folder) / name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
