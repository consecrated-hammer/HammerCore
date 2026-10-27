#!/usr/bin/env python3
"""Zip an addon's staged dev build and post it to the Discord dev-builds channel.

Usage: discord_dev.py <addon-dir> [--note TEXT] [--dry-run DIR]

It packages what stage.py already put in the client folders, so testers get
exactly the build the maintainer is running. Every staged client's TOC is included
with its -devN stamp, so `/<cmd> version` matches in Retail and WoW Forever.

The webhook is DEV_BUILDS_WEBHOOK_URL in the host automation env file. It is
never printed or written anywhere else.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
import uuid
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from stage import CLIENTS  # noqa: E402

ENV_FILE = Path("/mnt/docker/state/secrets/host-automation.env")
LIMIT = 10 * 1024 * 1024  # Discord's attachment limit for an unboosted server
LABELS = {"retail": "Retail", "forever": "WoW Forever"}


def webhook() -> str:
    url = os.environ.get("DEV_BUILDS_WEBHOOK_URL", "")
    if not url and ENV_FILE.is_file():
        for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
            key, _, value = line.partition("=")
            if key.strip() == "DEV_BUILDS_WEBHOOK_URL":
                url = value.strip().strip('"')
    if not url:
        raise SystemExit(f"DEV_BUILDS_WEBHOOK_URL is not set in {ENV_FILE}")
    return url


def stamped(toc: Path) -> str | None:
    match = re.search(r"^## Version:\s*(.+?-dev\d+)\s*$", toc.read_text(encoding="utf-8", errors="replace"), re.MULTILINE)
    return match.group(1) if match else None


def staged_build(name: str, clients: list[str] | None = None) -> tuple[str, Path, dict[str, Path]]:
    """The common dev version, a base folder and each client's stamped TOC.

    With clients, only those staged copies are packaged: staging one client
    leaves the other on its older -devN, which must not block the post.
    """
    tocs, base = {}, None
    for client, (root, pattern) in CLIENTS.items():
        if clients is not None and client not in clients:
            continue
        toc = root / name / pattern.format(name=name)
        if toc.is_file() and stamped(toc):
            tocs[client], base = toc, base or root / name
    if not tocs:
        raise SystemExit(f"no staged dev build of {name}; run stage.py first")
    versions = {stamped(toc) for toc in tocs.values()}
    if len(versions) != 1:
        raise SystemExit(f"staged clients disagree on the version: {sorted(versions)}; restage both")
    return versions.pop(), base, tocs


def build_zip(name: str, version: str, base: Path, tocs: dict[str, Path], out_dir: Path) -> Path:
    archive = out_dir / f"{name}-{version}.zip"
    overrides = {toc.name: toc for toc in tocs.values()}
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(base.rglob("*")):
            if path.is_file():
                relative = path.relative_to(base)
                source = overrides.get(relative.as_posix(), path)
                zf.write(source, f"{name}/{relative.as_posix()}")
    return archive


def source_state(source: Path) -> str:
    def git(*args: str) -> str:
        return subprocess.run(["git", "-C", str(source), *args], capture_output=True, text=True).stdout.strip()
    commit = git("rev-parse", "--short", "HEAD")
    if not commit:
        return "no commits yet"
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    dirty = " with uncommitted changes" if git("status", "--porcelain") else ""
    return f"`{branch}` at `{commit}`{dirty}"


def post(url: str, message: str, archive: Path) -> dict:
    boundary = uuid.uuid4().hex
    payload = json.dumps({"content": message, "allowed_mentions": {"parse": []}})
    body = b"".join([
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"payload_json\"\r\n"
        f"Content-Type: application/json\r\n\r\n{payload}\r\n".encode(),
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"files[0]\"; filename=\"{archive.name}\"\r\n"
        "Content-Type: application/zip\r\n\r\n".encode(),
        archive.read_bytes(),
        f"\r\n--{boundary}--\r\n".encode(),
    ])
    request = urllib.request.Request(f"{url}?wait=true", data=body, method="POST", headers={
        "Content-Type": f"multipart/form-data; boundary={boundary}",
        "User-Agent": "HammerCore-dev-builds (https://github.com/consecrated-hammer/HammerCore, 1)",
    })
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def publish(source: Path, note: str = "", dry_run: Path | None = None,
            clients: list[str] | None = None) -> Path:
    name = source.name
    version, base, tocs = staged_build(name, clients)
    clients = " + ".join(LABELS[c] for c in tocs)
    with tempfile.TemporaryDirectory() as temp:
        archive = build_zip(name, version, base, tocs, dry_run or Path(temp))
        size = archive.stat().st_size
        if size > LIMIT:
            raise SystemExit(f"{archive.name} is {size:,} bytes, over Discord's {LIMIT:,} byte limit")
        lines = [f"**{name} {version}** for {clients}", f"Source: {source_state(source)}"]
        if note:
            lines.append(note)
        lines.append(f"Dev build for testing, not a release. Unzip into `Interface/AddOns`, replacing any old "
                     f"`{name}` folder, then check `/{name.lower()} version` in game.")
        message = "\n".join(lines)
        if dry_run:
            print(message)
            print(f"Built {archive} ({size:,} bytes); nothing posted")
            return archive
        result = post(webhook(), message, archive)
        attached = [a.get("filename") for a in result.get("attachments", [])]
        if archive.name not in attached:
            raise SystemExit(f"Discord accepted the message but not the attachment: {attached}")
        print(f"Posted {archive.name} ({size:,} bytes) to Discord")
        return archive


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("addon", type=Path)
    parser.add_argument("--note", default="", help="one line about what changed")
    parser.add_argument("--dry-run", type=Path, metavar="DIR", help="build the zip into DIR and print the message only")
    args = parser.parse_args()
    publish(args.addon.resolve(), args.note, args.dry_run)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
