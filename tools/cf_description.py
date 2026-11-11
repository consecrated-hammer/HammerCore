#!/usr/bin/env python3
"""Publish an addon's CurseForge description from the wiki.

Usage: cf_description.py <Addon>... [--all] [--save] [--out DIR]

It drives the logged-in Chromium in the cf-browser container (see
/mnt/docker/infra/docs/cf-browser.md): opens each project's description page,
compares the live Markdown with wiki/curseforge/descriptions/<Addon>.md and,
when they differ, fills the editor and takes a screenshot. Nothing is saved
without --save. With --save it clicks Save, reloads and checks the live text
matches the file.

CurseForge reflows Markdown when it saves (bullets, wrapping, URL encoding),
so the comparison is on normalised text, not bytes.

The browser work runs in a throwaway Playwright container that joins
cf-browser's network namespace, the only place its debug port is reachable.
The project ID comes from the addon's TOC (X-Curse-Project-ID).
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
import time
import urllib.parse
from pathlib import Path

ADDONS = Path("/mnt/docker/apps/wow-addons")
DESCRIPTIONS = Path(
    "/mnt/docker/agentwiki-consecrated-hammer/workstreams/wow-addons/knowledge/wiki/curseforge/descriptions"
)
CONTAINER = "cf-browser"
PLAYWRIGHT = "1.55.0"
BASE_IMAGE = f"mcr.microsoft.com/playwright/python:v{PLAYWRIGHT}-noble"
RUNNER_IMAGE = f"hammercore-cf-runner:{PLAYWRIGHT}"
CDP = "http://127.0.0.1:9222"
EDITOR_URL = "https://authors.curseforge.com/#/projects/{pid}/description"


def normalise(text: str) -> str:
    """Reduce Markdown to what CurseForge preserves when it saves."""
    text = text.replace("\r\n", "\n")
    text = re.sub(r"\]\(<([^>]*)>\)", r"](\1)", text)
    text = urllib.parse.unquote(text)
    text = re.sub(r"(?m)^\s*[*+-]\s+", "- ", text)
    text = re.sub(r"(?m)^\s*(\d+)[.)]\s+", r"\1. ", text)
    # Keep paragraph breaks and hard line breaks (<br>, or the two trailing
    # spaces CurseForge stores it as) distinct; plain newlines are reflow.
    text = re.sub(r"<br\s*/?>", "\u21b5", text, flags=re.I)
    text = re.sub(r" {2,}\n", "\u21b5", text)
    text = re.sub(r"\n[ \t]*\n\s*", "\u00b6", text)
    text = re.sub(r"(?<!\*)\*(?!\*)([^*\n\u00b6\u21b5]+?)(?<!\*)\*(?!\*)", r"_\1_", text)
    text = text.replace("\\", "")
    text = re.sub(r"\s*([\u21b5\u00b6])\s*", r"\1", text)
    return re.sub(r"\s+", " ", text).strip()


def first_difference(live: str, wanted: str) -> str:
    a, b = normalise(live), normalise(wanted)
    i = next((n for n, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
    return f"live: ...{a[max(0, i - 40):i + 60]!r}\n  file: ...{b[max(0, i - 40):i + 60]!r}"


def sent_text_matches(post_data: str | None, wanted: str) -> bool:
    """True when the save request carries our text.

    The editor sends the rendered HTML, so check that every link and image
    URL in the Markdown made it into the body. Old text would be missing the
    new ones.
    """
    try:
        body = json.loads(post_data or "")
    except ValueError:
        return False
    html = body.get("description") if isinstance(body, dict) else None
    if not isinstance(html, str):
        return False
    html = html.replace("&amp;", "&")
    urls = re.findall(r"\]\(<?(https?://[^)\s>]+)>?\)", wanted)
    return bool(urls) and all(url in html for url in urls)


# ── Inside the runner container ─────────────────────────────────────────────


def run_inside(args: argparse.Namespace) -> int:
    from playwright.sync_api import TimeoutError as PWTimeout
    from playwright.sync_api import sync_playwright

    failures = 0
    with sync_playwright() as p:
        browser = p.chromium.connect_over_cdp(CDP)
        context = browser.contexts[0]
        for job in args.jobs:
            name, pid = job.split("=", 1)
            wanted = Path(f"/desc/{name}.md").read_text(encoding="utf-8")
            page = context.new_page()
            try:
                status = publish(page, name, pid, wanted, args.save, PWTimeout)
            except Exception as err:  # report and carry on with the next addon
                page.screenshot(path=f"/out/{name}-error.png")
                status = f"FAIL: {err.__class__.__name__}: {str(err).splitlines()[0]} (screenshot {name}-error.png)"
            finally:
                page.close()
            print(f"{name}: {status}", flush=True)
            failures += status.startswith("FAIL")
    return 1 if failures else 0


def open_editor(page, pid: str, timeout_error):
    page.goto(EDITOR_URL.format(pid=pid), wait_until="networkidle", timeout=60000)
    editor = page.locator("textarea.mde-text")
    try:
        editor.wait_for(state="visible", timeout=30000)
    except timeout_error:
        raise RuntimeError(
            "no Markdown editor on the page. Logged out, or the project isn't set to Markdown? "
            "Check https://cfbrowser.batserver.au"
        ) from None
    return editor


def publish(page, name: str, pid: str, wanted: str, save: bool, timeout_error) -> str:
    editor = open_editor(page, pid, timeout_error)
    live = editor.input_value()
    if normalise(live) == normalise(wanted):
        return "up to date"
    print(f"{name}: differs from the file\n  {first_difference(live, wanted)}", flush=True)

    editor.fill(wanted)
    if editor.input_value() != wanted:
        return "FAIL: the editor didn't take the new text"
    page.screenshot(path=f"/out/{name}-filled.png", full_page=True)
    if not save:
        return f"would update (not saved; screenshot {name}-filled.png)"

    # Let the editor register the new text before saving; clicking straight
    # away can save the old text.
    page.wait_for_timeout(1500)
    with page.expect_response(
        lambda r: r.request.method == "PUT" and f"/_api/projects/description/{pid}" in r.url,
        timeout=30000,
    ) as response_info:
        page.get_by_role("button", name="Save", exact=True).click()
    response = response_info.value
    if not response.ok:
        page.screenshot(path=f"/out/{name}-save-error.png", full_page=True)
        return f"FAIL: save returned HTTP {response.status}"
    if not sent_text_matches(response.request.post_data, wanted):
        return "FAIL: the save request didn't carry the new text (clicked too early?)"

    # CurseForge can serve the old text for a little while after a save, so
    # reload a few times before calling it a mismatch. The editor is a
    # single-page app: going to the same URL is only a hash change, so
    # reload for real.
    for attempt in range(6):
        page.wait_for_timeout(5000 if attempt else 1500)
        page.reload(wait_until="networkidle", timeout=60000)
        editor = page.locator("textarea.mde-text")
        editor.wait_for(state="visible", timeout=30000)
        if normalise(editor.input_value()) == normalise(wanted):
            break
    else:
        page.screenshot(path=f"/out/{name}-after-save.png", full_page=True)
        return f"FAIL: saved, but the live text still doesn't match after 30 s (screenshot {name}-after-save.png)"
    return "saved and checked"


# ── On the host ─────────────────────────────────────────────────────────────


def project_id(addon: str) -> str:
    for toc in sorted((ADDONS / addon).glob("*.toc")):
        match = re.search(r"^## X-Curse-Project-ID:\s*(\d+)", toc.read_text(encoding="utf-8"), re.M)
        if match:
            return match.group(1)
    raise SystemExit(f"{addon}: no X-Curse-Project-ID in {ADDONS / addon}/*.toc")


def ensure_runner_image() -> None:
    have = subprocess.run(["docker", "image", "inspect", RUNNER_IMAGE], capture_output=True)
    if have.returncode == 0:
        return
    print(f"Building {RUNNER_IMAGE} (once)...", flush=True)
    dockerfile = f"FROM {BASE_IMAGE}\nRUN pip install --no-cache-dir --break-system-packages playwright=={PLAYWRIGHT}\n"
    subprocess.run(["docker", "build", "-q", "-t", RUNNER_IMAGE, "-"], input=dockerfile.encode(), check=True)


def browser_ready() -> bool:
    probe = (
        "import urllib.request,sys;"
        f"urllib.request.urlopen('{CDP}/json/version', timeout=3);sys.exit(0)"
    )
    result = subprocess.run(
        ["docker", "run", "--rm", "--network", f"container:{CONTAINER}", RUNNER_IMAGE, "python", "-c", probe],
        capture_output=True,
    )
    return result.returncode == 0


def ensure_browser() -> None:
    """Restart cf-browser when Chromium has been closed in the web view."""
    if browser_ready():
        return
    print(f"Chromium isn't running in {CONTAINER}; restarting it...", flush=True)
    subprocess.run(["docker", "restart", CONTAINER], check=True, capture_output=True)
    for _ in range(30):
        if browser_ready():
            return
        time.sleep(2)
    raise SystemExit(f"Chromium didn't come back in {CONTAINER}.")


def run_host(args: argparse.Namespace) -> int:
    names = sorted(p.stem for p in args.descriptions.glob("*.md")) if args.all else args.addons
    if not names:
        raise SystemExit("Name at least one addon, or pass --all.")
    jobs = []
    for name in names:
        if not (args.descriptions / f"{name}.md").is_file():
            raise SystemExit(f"{name}: no {args.descriptions / (name + '.md')}")
        jobs.append(f"{name}={project_id(name)}")

    running = subprocess.run(
        ["docker", "inspect", "-f", "{{.State.Running}}", CONTAINER], capture_output=True, text=True
    )
    if running.stdout.strip() != "true":
        raise SystemExit(f"The {CONTAINER} container isn't running.")
    ensure_runner_image()
    ensure_browser()

    out = args.out or Path(tempfile.mkdtemp(prefix="cf-description-"))
    out.mkdir(parents=True, exist_ok=True)
    script = Path(__file__).resolve()
    command = [
        "docker", "run", "--rm", "--network", f"container:{CONTAINER}",
        "--user", "1000:1000", "-e", "HOME=/tmp",
        "-v", f"{script}:/tool/cf_description.py:ro",
        "-v", f"{args.descriptions}:/desc:ro",
        "-v", f"{out}:/out",
        RUNNER_IMAGE, "python", "/tool/cf_description.py", "--inside",
        *(["--save"] if args.save else []), *jobs,
    ]
    result = subprocess.run(command)
    print(f"Screenshots: {out}")
    return result.returncode


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("addons", nargs="*", help="addon names, e.g. Salve")
    parser.add_argument("--all", action="store_true", help="every description file in the wiki")
    parser.add_argument("--save", action="store_true", help="save to CurseForge (default: fill and screenshot only)")
    parser.add_argument("--out", type=Path, help="screenshot folder (default: a new temp folder)")
    parser.add_argument("--descriptions", type=Path, default=DESCRIPTIONS, help=argparse.SUPPRESS)
    parser.add_argument("--inside", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if args.inside:
        args.jobs = args.addons
        return run_inside(args)
    return run_host(args)


if __name__ == "__main__":
    sys.exit(main())
