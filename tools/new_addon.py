#!/usr/bin/env python3
"""Scaffold a new Consecrated Hammer addon on HammerCore.

Usage: new_addon.py <Name> [--command cmd] [--dest DIR]

Creates a repository with Retail and Forever TOCs, HammerCore vendored and
wired in, one example settings page and command, a test, Lint and guarded
Release workflows, packaging metadata, a changelog and the GPL licence.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEMPLATES = ROOT / "tools" / "templates"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("name", help="addon folder and display name, e.g. Anvilwise")
    parser.add_argument("--command", help="slash command without the slash (default: lowercase name)")
    parser.add_argument("--dest", type=Path, help="destination (default: next to HammerCore)")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Z][A-Za-z0-9]+", args.name):
        raise SystemExit("name must be CamelCase letters and digits, e.g. Anvilwise")
    command = (args.command or args.name.lower()).lstrip("/")
    dest = (args.dest or ROOT.parent / args.name).resolve()
    if dest.exists():
        raise SystemExit(f"{dest} already exists")

    values = {"NAME": args.name, "COMMAND": command, "SLUG": args.name.lower(),
              "KEY": re.sub(r"[^A-Z0-9]", "", args.name.upper())}

    def fill(text: str) -> str:
        return re.sub(r"\{\{(\w+)\}\}", lambda m: values[m.group(1)], text)

    for source in TEMPLATES.rglob("*"):
        if source.is_dir():
            continue
        target = dest / fill(source.relative_to(TEMPLATES).as_posix())
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(fill(source.read_text(encoding="utf-8")), encoding="utf-8")
    shutil.copy2(ROOT / "LICENSE.txt", dest / "LICENSE.txt")
    (dest / "Textures").mkdir(exist_ok=True)

    subprocess.run(["git", "init", "-q", "-b", "main", str(dest)], check=True)
    subprocess.run([sys.executable, str(ROOT / "tools" / "sync.py"), str(dest)], check=True)
    print(f"Created {args.name} at {dest}")
    print("Next: add Textures/" + args.name + ".tga, run the tests, commit, then create the GitHub repo.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
