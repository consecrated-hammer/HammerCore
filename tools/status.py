#!/usr/bin/env python3
"""Report what's parked across every addon repository.

Usage: status.py [--write] [--root DIR] [--wiki DIR] [--retail DIR] [--forever DIR]

For each addon under --root (default /mnt/docker/apps/wow-addons: every
folder with a .git and a TOC, plus HammerCore) it shows uncommitted files,
commits not pushed (against the local tracking ref; nothing is fetched), the
vendored HammerCore against the current src/Core.lua, the TOC version, the
build staged in each client (read from the staged TOC that client loads), an
[Unreleased] CHANGELOG section with notes in it, and whether the CurseForge
description is waiting to be pasted (from the wiki's Description
maintenance table).

It only reads.  --write also writes the AgentWiki page addon-status.md in
--wiki (default the wow-addons workstream wiki).
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
from stage import CLIENTS  # noqa: E402

ROOT = Path("/mnt/docker/apps/wow-addons")
WIKI = Path("/mnt/docker/agentwiki-consecrated-hammer/workstreams/wow-addons/knowledge/wiki")
DESCRIPTIONS = Path("curseforge") / "description-maintenance.md"
PAGE = "addon-status.md"
STALE_DAYS = 7
COLUMNS = ["Addon", "Dirty", "Ahead", "HammerCore", "TOC", "Retail", "Forever", "Unreleased", "CF description"]


@dataclass
class Status:
    name: str
    dirty: int | None = None
    ahead: int | None = None
    vendored: str | None = None
    vendored_note: str | None = None  # why the vendored copy isn't current
    toc: str | None = None
    staged: dict[str, str | None] = field(default_factory=dict)
    unreleased: str = "-"  # notes, empty, none, no changelog
    description: str = "-"  # pending, pasted, or - when not listed
    description_note: str = ""


def git(repo: Path, *args: str) -> tuple[int, str]:
    result = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)
    return result.returncode, result.stdout


def discover(root: Path) -> list[Path]:
    found = []
    for path in sorted(root.iterdir()):
        if not path.is_dir() or not (path / ".git").exists():
            continue
        if path.name == "HammerCore" or any(path.glob("*.toc")):
            found.append(path)
    return found


def dirty_count(repo: Path) -> int | None:
    code, out = git(repo, "status", "--porcelain", "--untracked-files=all")
    return len([line for line in out.splitlines() if line.strip()]) if code == 0 else None


def ahead_count(repo: Path) -> int | None:
    code, out = git(repo, "rev-list", "--count", "@{upstream}..HEAD")
    return int(out.strip()) if code == 0 and out.strip().isdigit() else None


def hc_version(hammercore: Path) -> str | None:
    core = hammercore / "src" / "Core.lua"
    if not core.is_file():
        return None
    match = re.search(r'HC\.VERSION = "([^"]+)"', core.read_text(encoding="utf-8", errors="replace"))
    return match.group(1) if match else None


def vendored(addon: Path, hammercore: Path, current: str | None) -> tuple[str | None, str | None]:
    """(vendored version, why it isn't current or None)."""
    stamp = addon / "Libs" / "HammerCore" / "VERSION"
    if not stamp.is_file():
        return None, None
    fields = dict(line.split("=", 1) for line in stamp.read_text(encoding="utf-8").split() if "=" in line)
    version, commit = fields.get("version"), fields.get("commit", "")
    if current and version != current:
        return version, f"vendored HammerCore {version}, current {current}"
    code, _ = git(hammercore, "cat-file", "-e", f"{commit}^{{commit}}")
    if not commit or code != 0:
        return version, f"vendored HammerCore pin {commit[:7] or 'missing'} isn't in the HammerCore checkout"
    code, _ = git(hammercore, "diff", "--quiet", commit, "HEAD", "--", "src")
    if code != 0:
        return version, f"vendored HammerCore pinned to {commit[:7]}; src/ has changed since"
    return version, None


def toc_version(toc: Path) -> str | None:
    if not toc.is_file():
        return None
    match = re.search(r"^## Version:\s*(.+?)\s*$", toc.read_text(encoding="utf-8", errors="replace"), re.MULTILINE)
    return match.group(1) if match else None


def toc_versions(addon: Path) -> str | None:
    versions = sorted({v for v in (toc_version(toc) for toc in addon.glob("*.toc")) if v})
    return "/".join(versions) if versions else None


def staged(addon: Path, clients: dict[str, tuple[Path, str]]) -> dict[str, str | None]:
    """Client -> staged version; n/a for a client the addon has no TOC for."""
    name = addon.name
    found = {}
    for client, (folder, toc) in clients.items():
        toc_name = toc.format(name=name)
        found[client] = toc_version(folder / name / toc_name) if (addon / toc_name).is_file() else "n/a"
    return found


def unreleased(addon: Path) -> str:
    changelog = addon / "CHANGELOG.md"
    if not changelog.is_file():
        return "no changelog"
    text = changelog.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"^## \[Unreleased\][^\n]*\n(.*?)(?=^## |\Z)", text, re.MULTILINE | re.DOTALL | re.IGNORECASE)
    if not match:
        return "none"
    return "notes" if any(line.strip() for line in match.group(1).splitlines()) else "empty"


def pending(paste_status: str) -> bool:
    text = paste_status.lower()
    return not re.search(r"\bpasted\b", text) or bool(re.search(r"\b(not|awaiting|needed|needs)\b", text))


def descriptions(page: Path) -> dict[str, tuple[bool, str]]:
    """Addon -> (paste pending, paste status text) from the description table."""
    if not page.is_file():
        return {}
    found: dict[str, tuple[bool, str]] = {}
    header: list[str] | None = None
    for line in page.read_text(encoding="utf-8").splitlines():
        if not line.startswith("|"):
            header = None
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if header is None:
            header = [cell.lower() for cell in cells]
            continue
        if set("".join(cells)) <= set("-: "):
            continue
        if "addon" not in header or "paste status" not in header:
            continue
        row = dict(zip(header, cells))
        name, status = row.get("addon", ""), row.get("paste status", "")
        if name:
            found[name] = (pending(status), status)
    return found


def collect(root: Path, wiki: Path, clients: dict[str, tuple[Path, str]]) -> list[Status]:
    hammercore = root / "HammerCore"
    current = hc_version(hammercore)
    listed = descriptions(wiki / DESCRIPTIONS)
    report = []
    for repo in discover(root):
        status = Status(repo.name, dirty_count(repo), ahead_count(repo))
        status.unreleased = unreleased(repo)
        if repo.name == "HammerCore":
            status.vendored = current
        else:
            status.vendored, status.vendored_note = vendored(repo, hammercore, current)
            status.toc = toc_versions(repo)
            status.staged = staged(repo, clients)
        if repo.name in listed:
            is_pending, text = listed[repo.name]
            status.description = "pending" if is_pending else "pasted"
            status.description_note = text
        report.append(status)
    return report


def cells(status: Status) -> list[str]:
    hc = status.vendored or "-"
    if status.vendored_note and status.vendored:
        hc += " (old)"
    return [
        status.name,
        "?" if status.dirty is None else str(status.dirty),
        "no upstream" if status.ahead is None else str(status.ahead),
        hc,
        status.toc or "-",
        status.staged.get("retail") or "-",
        status.staged.get("forever") or "-",
        status.unreleased,
        status.description,
    ]


def attention(report: list[Status]) -> list[str]:
    items = []
    for status in report:
        name = status.name
        if status.dirty:
            items.append(f"{name}: {status.dirty} uncommitted file(s)")
        if status.ahead:
            items.append(f"{name}: {status.ahead} commit(s) not pushed")
        if status.vendored_note:
            items.append(f"{name}: {status.vendored_note}")
        if status.unreleased == "notes":
            items.append(f"{name}: CHANGELOG [Unreleased] has notes")
        if status.description == "pending":
            items.append(f"{name}: CurseForge description waiting to be pasted ({status.description_note})")
    return items


def text_table(rows: list[list[str]]) -> str:
    widths = [max(len(row[i]) for row in rows) for i in range(len(rows[0]))]
    lines = ["  ".join(cell.ljust(widths[i]) for i, cell in enumerate(row)).rstrip() for row in rows]
    lines.insert(1, "  ".join("-" * width for width in widths))
    return "\n".join(lines)


def markdown_table(rows: list[list[str]]) -> str:
    escaped = [[cell.replace("|", "\\|") for cell in row] for row in rows]
    lines = ["| " + " | ".join(escaped[0]) + " |", "|" + "---|" * len(escaped[0])]
    lines += ["| " + " | ".join(row) + " |" for row in escaped[1:]]
    return "\n".join(lines)


def page(report: list[Status], root: Path, wiki: Path, clients: dict[str, tuple[Path, str]], now: datetime) -> str:
    rows = [COLUMNS] + [cells(status) for status in report]
    sources = [root / status.name for status in report]
    sources += [wiki / DESCRIPTIONS] + [folder for folder, _ in clients.values()]
    items = attention(report)
    lines = [
        "---",
        "type: status",
        "status: active",
        "verified:",
        "  by: HammerCore tools/status.py",
        f'  at: "{now.isoformat(timespec="seconds")}"',
        f"stale_after: {(now + timedelta(days=STALE_DAYS)).date().isoformat()}",
        "sources:",
        *[f"  - resource: {source}" for source in sources],
        "---",
        "# Addon status",
        "",
        "Generated by HammerCore `tools/status.py --write`, so don't edit it by hand; rerun the tool instead.",
        "",
        markdown_table(rows),
        "",
        "Dirty is uncommitted files. Ahead is commits not pushed, against the local tracking ref.",
        "HammerCore is the vendored version, marked old when it isn't the current one.",
        "Retail and Forever are the versions in the staged client TOCs; n/a means the addon has no TOC for that client.",
        "",
        "## Needs attention",
        "",
        *([f"- {item}" for item in items] or ["- Nothing."]),
        "",
    ]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=ROOT, help="folder holding the addon repositories")
    parser.add_argument("--wiki", type=Path, default=WIKI, help="the wow-addons workstream wiki folder")
    parser.add_argument("--retail", type=Path, default=CLIENTS["retail"][0], help="Retail AddOns folder")
    parser.add_argument("--forever", type=Path, default=CLIENTS["forever"][0], help="Forever AddOns folder")
    parser.add_argument("--write", action="store_true", help=f"also write {PAGE} in the wiki")
    args = parser.parse_args(argv)
    clients = {"retail": (args.retail, CLIENTS["retail"][1]), "forever": (args.forever, CLIENTS["forever"][1])}
    root, wiki = args.root.resolve(), args.wiki.resolve()
    report = collect(root, wiki, clients)
    if not report:
        print(f"no addon repositories under {root}")
        return 1
    print(text_table([COLUMNS] + [cells(status) for status in report]))
    items = attention(report)
    print()
    print("Needs attention:")
    for item in items or ["Nothing."]:
        print(f"  {item}")
    if args.write:
        target = wiki / PAGE
        target.write_text(page(report, root, wiki, clients, datetime.now().astimezone()), encoding="utf-8")
        print(f"\nWrote {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
