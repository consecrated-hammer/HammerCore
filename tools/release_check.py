#!/usr/bin/env python3
"""Run everything a release needs and print one PASS or FAIL.

Usage: release_check.py <addon> --version X.Y.Z [--allow-dirty] [--skip-tests] [--lua PATH]

<addon> is a name under /mnt/docker/apps/wow-addons (or any path to an addon
checkout).  Steps, each printed as one PASS/FAIL/WARN/SKIP line:

  toc        tools/toc_check.py: every TOC loads exactly the addon's Lua
  version    every TOC says ## Version: X; an X-ReleaseDate matches CHANGELOG
  whatsnew   tools/whatsnew_check.py --version X
  hammercore tools/check.py: the vendored copy matches its pinned commit
  lua        tests/test_*.lua and tests/*_test.lua under Lua 5.1, run from
             the addon root in the nickblah/lua:5.1-alpine container
  python     tests/test_*.py, if the addon has any
  changelog  CHANGELOG.md has a `## [X] - YYYY-MM-DD` heading
  git        the working tree is clean apart from release files (CHANGELOG.md,
             TOCs and the Lua files holding What's new entries)

Every step runs even after a failure, so one run shows every problem.
--allow-dirty turns a dirty tree into a warning.  --skip-tests skips the Lua
and Python tests.  --lua PATH runs Lua tests with a local interpreter instead
of Docker.  Exit code 0 means the release can go ahead.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
ADDONS = Path("/mnt/docker/apps/wow-addons")
LUA_IMAGE = "nickblah/lua:5.1-alpine"
TEST_TIMEOUT = 600

sys.path.insert(0, str(TOOLS))
import whatsnew_check  # noqa: E402


@dataclass
class Result:
    status: str  # PASS, FAIL, WARN or SKIP
    reason: str
    details: list[str] = field(default_factory=list)


def run(command: list[str], cwd: Path, timeout: int = TEST_TIMEOUT) -> tuple[int, str]:
    try:
        result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError as error:
        return 127, f"can't run {command[0]}: {error.strerror}"
    except subprocess.TimeoutExpired:
        return 124, f"timed out after {timeout}s"
    return result.returncode, (result.stdout + result.stderr).strip()


def tool(name: str, addon: Path, *extra: str) -> tuple[int, list[str]]:
    code, output = run([sys.executable, str(TOOLS / name), str(addon), *extra], cwd=addon)
    return code, [line for line in output.splitlines() if line.strip()]


def failure(problems: list[str], what: str) -> Result:
    """One problem goes on the step line; several are counted and listed."""
    if len(problems) == 1:
        return Result("FAIL", problems[0])
    return Result("FAIL", f"{len(problems)} {what}", problems)


def plain(version: str) -> str:
    return version[1:] if version.startswith("v") else version


def toc_versions(addon: Path) -> dict[str, tuple[str | None, str | None]]:
    """TOC name -> (## Version, ## X-ReleaseDate)."""
    found = {}
    for toc in sorted(addon.glob("*.toc")):
        text = toc.read_text(encoding="utf-8", errors="replace")
        version = re.search(r"^## Version:\s*(.+?)\s*$", text, re.MULTILINE)
        date = re.search(r"^## X-ReleaseDate:\s*(.+?)\s*$", text, re.MULTILINE)
        found[toc.name] = (version.group(1) if version else None, date.group(1) if date else None)
    return found


def changelog_date(addon: Path, version: str) -> str | None:
    changelog = addon / "CHANGELOG.md"
    if not changelog.is_file():
        return None
    match = re.search(r"^## \[" + re.escape(version) + r"\] - (\d{4}-\d{2}-\d{2})\s*$",
                      changelog.read_text(encoding="utf-8", errors="replace"), re.MULTILINE)
    return match.group(1) if match else None


def check_toc(addon: Path, version: str) -> Result:
    code, lines = tool("toc_check.py", addon)
    if code == 0:
        return Result("PASS", f"{len(lines)} TOC(s) load every Lua file")
    return failure([line for line in lines if "loads all" not in line], "TOC problems")


def check_version(addon: Path, version: str) -> Result:
    tocs = toc_versions(addon)
    if not tocs:
        return Result("FAIL", "no TOC files")
    problems = []
    date = changelog_date(addon, version)
    for name, (found, released) in tocs.items():
        if found != version:
            problems.append(f"{name} says {found or 'no version'}, not {version}")
        if released and date and released != date:
            problems.append(f"{name} X-ReleaseDate {released} doesn't match CHANGELOG {date}")
    if problems:
        return failure(problems, "TOC version problems")
    return Result("PASS", f"{len(tocs)} TOC(s) at {version}")


def check_whatsnew(addon: Path, version: str) -> Result:
    code, lines = tool("whatsnew_check.py", addon, "--version", version)
    if code == 0:
        return Result("PASS", lines[-1] if lines else "covered")
    return failure(lines, "missing entries")


def check_hammercore(addon: Path, version: str) -> Result:
    code, lines = tool("check.py", addon)
    if code == 0:
        return Result("PASS", lines[-1] if lines else "verified")
    return Result("FAIL", lines[0] if lines else f"check.py exited {code}", lines[1:])


def lua_tests(addon: Path) -> list[str]:
    tests = addon / "tests"
    found = set(tests.glob("test_*.lua")) | set(tests.glob("*_test.lua"))
    return sorted(path.relative_to(addon).as_posix() for path in found if path.is_file())


def lua_command(addon: Path, test: str, lua: str | None) -> list[str]:
    if lua:
        return [lua, test]
    return ["docker", "run", "--rm", "-v", f"{addon}:/w", "-w", "/w", LUA_IMAGE, "lua", test]


def last_line(output: str) -> str:
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    return lines[-1][:160] if lines else "no output"


def check_lua(addon: Path, version: str, lua: str | None = None) -> Result:
    tests = lua_tests(addon)
    if not tests:
        return Result("WARN", "no Lua tests found")
    failed = []
    for test in tests:
        code, output = run(lua_command(addon, test, lua), cwd=addon)
        if code != 0:
            failed.append(f"{test}: {last_line(output)}")
    if failed:
        return Result("FAIL", f"{len(failed)} of {len(tests)} Lua tests failed", failed)
    return Result("PASS", f"{len(tests)} Lua tests passed")


def check_python(addon: Path, version: str) -> Result:
    tests = sorted(path.relative_to(addon).as_posix() for path in (addon / "tests").glob("test_*.py"))
    if not tests:
        return Result("SKIP", "no Python tests")
    failed = []
    for test in tests:
        code, output = run([sys.executable, test], cwd=addon)
        if code != 0:
            failed.append(f"{test}: {last_line(output)}")
    if failed:
        return Result("FAIL", f"{len(failed)} of {len(tests)} Python test files failed", failed)
    return Result("PASS", f"{len(tests)} Python test file(s) passed")


def check_changelog(addon: Path, version: str) -> Result:
    if not (addon / "CHANGELOG.md").is_file():
        return Result("FAIL", "no CHANGELOG.md")
    date = changelog_date(addon, version)
    if date:
        return Result("PASS", f"## [{version}] - {date}")
    return Result("FAIL", f"no '## [{version}] - YYYY-MM-DD' heading")


def release_files(addon: Path) -> set[str]:
    """Files a release commit is expected to touch."""
    allowed = {"CHANGELOG.md"} | {toc.name for toc in addon.glob("*.toc")}
    for path in addon.rglob("*.lua"):
        relative = path.relative_to(addon)
        if any(part in whatsnew_check.SKIP for part in relative.parts):
            continue
        if whatsnew_check.ENTRY.search(path.read_text(encoding="utf-8", errors="replace")):
            allowed.add(relative.as_posix())
    return allowed


def dirty_files(addon: Path) -> list[str] | None:
    # Not run(): its strip() would eat the leading space of the first status line.
    result = subprocess.run(["git", "-C", str(addon), "status", "--porcelain", "--untracked-files=all"],
                            capture_output=True, text=True)
    if result.returncode != 0:
        return None
    files = []
    for line in result.stdout.splitlines():
        name = line[3:]
        if " -> " in name:
            name = name.split(" -> ", 1)[1]
        files.append(name.strip('"'))
    return files


def check_git(addon: Path, version: str, allow_dirty: bool = False) -> Result:
    files = dirty_files(addon)
    if files is None:
        return Result("FAIL", "not a git repository")
    allowed = release_files(addon)
    other = [name for name in files if name not in allowed]
    if not other:
        changed = len(files)
        return Result("PASS", f"clean apart from {changed} release file(s)" if changed else "clean")
    reason = f"{len(other)} uncommitted file(s) outside the release files"
    return Result("WARN" if allow_dirty else "FAIL", reason + (" (--allow-dirty)" if allow_dirty else ""), other)


def resolve(addon: str) -> Path:
    path = Path(addon)
    if not path.exists() and not path.is_absolute() and (ADDONS / addon).is_dir():
        path = ADDONS / addon
    return path.resolve()


def checks(args: argparse.Namespace) -> list[tuple[str, callable]]:
    steps = [("toc", check_toc), ("version", check_version), ("whatsnew", check_whatsnew),
             ("hammercore", check_hammercore)]
    if args.skip_tests:
        steps += [("lua", lambda a, v: Result("SKIP", "--skip-tests")),
                  ("python", lambda a, v: Result("SKIP", "--skip-tests"))]
    else:
        steps += [("lua", lambda a, v: check_lua(a, v, args.lua)), ("python", check_python)]
    steps += [("changelog", check_changelog), ("git", lambda a, v: check_git(a, v, args.allow_dirty))]
    return steps


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("addon", help="addon name under /mnt/docker/apps/wow-addons, or a path")
    parser.add_argument("--version", required=True, help="the version being released (with or without v)")
    parser.add_argument("--allow-dirty", action="store_true", help="warn about uncommitted files instead of failing")
    parser.add_argument("--skip-tests", action="store_true", help="skip the Lua and Python tests")
    parser.add_argument("--lua", help="run Lua tests with this local interpreter instead of Docker")
    args = parser.parse_args(argv)
    addon = resolve(args.addon)
    if not addon.is_dir():
        print(f"FAIL {args.addon}: no such addon")
        return 1
    version = plain(args.version)
    print(f"Release check: {addon.name} {version}")
    failed = False
    for name, step in checks(args):
        try:
            result = step(addon, version)
        except Exception as error:  # a broken step must not hide the others
            result = Result("FAIL", f"{type(error).__name__}: {error}")
        print(f"{result.status:<4} {name:<10} {result.reason}")
        for detail in result.details:
            print(f"     {'':<10}   {detail}")
        failed = failed or result.status == "FAIL"
    print("FAIL" if failed else "PASS")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
