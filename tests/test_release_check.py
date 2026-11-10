#!/usr/bin/env python3
"""tools/release_check.py: each step, and a run that keeps going after failures."""

from __future__ import annotations

import contextlib
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import release_check  # noqa: E402

GIT_ENV = {**os.environ, "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.invalid",
           "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.invalid"}

CHANGELOG = """# Changelog

## [Unreleased]

## [1.2.0] - 2026-11-10

- Quick play.

## [1.1.0] - 2026-11-01
"""


def git(repo: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, env=GIT_ENV)


class ReleaseCheckTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.temp)
        self.addon = self.temp / "Demo"
        (self.addon / "tests").mkdir(parents=True)
        for toc in ("Demo.toc", "Demo_Camelot.toc"):
            (self.addon / toc).write_text("## Version: 1.2.0\n## X-ReleaseDate: 2026-11-10\nCore.lua\n")
        (self.addon / "Core.lua").write_text("local x = 1\n")
        (self.addon / "WhatsNew.lua").write_text('ns.W = { { version = "1.2.0", items = {} } }\n')
        (self.addon / "CHANGELOG.md").write_text(CHANGELOG)
        git(self.addon, "init", "-q")
        git(self.addon, "add", "-A")
        git(self.addon, "commit", "-q", "-m", "init")

    def test_toc_versions_must_match_the_release(self):
        self.assertEqual(release_check.check_version(self.addon, "1.2.0").status, "PASS")
        result = release_check.check_version(self.addon, "1.3.0")
        self.assertEqual(result.status, "FAIL")
        self.assertEqual(len(result.details), 2)

    def test_release_date_must_match_the_changelog(self):
        (self.addon / "Demo.toc").write_text("## Version: 1.2.0\n## X-ReleaseDate: 2026-11-09\n")
        result = release_check.check_version(self.addon, "1.2.0")
        self.assertEqual(result.status, "FAIL")
        self.assertIn("X-ReleaseDate", result.reason)

    def test_changelog_needs_a_dated_heading(self):
        self.assertEqual(release_check.check_changelog(self.addon, "1.2.0").status, "PASS")
        self.assertEqual(release_check.check_changelog(self.addon, "1.3.0").status, "FAIL")
        (self.addon / "CHANGELOG.md").write_text("## [1.3.0] — 2026-11-10\n")
        self.assertEqual(release_check.check_changelog(self.addon, "1.3.0").status, "FAIL", "an em dash is refused")

    def test_release_files_may_be_dirty(self):
        self.assertEqual(release_check.check_git(self.addon, "1.2.0").reason, "clean")
        for name in ("CHANGELOG.md", "Demo.toc", "WhatsNew.lua"):
            (self.addon / name).write_text((self.addon / name).read_text() + "\n")
        result = release_check.check_git(self.addon, "1.2.0")
        self.assertEqual(result.status, "PASS")
        self.assertIn("3 release file", result.reason)

    def test_other_dirty_files_fail_or_warn(self):
        (self.addon / "Core.lua").write_text("local x = 2\n")
        (self.addon / ".pkgmeta").write_text("package-as: Demo\n")
        result = release_check.check_git(self.addon, "1.2.0")
        self.assertEqual(result.status, "FAIL")
        self.assertEqual(sorted(result.details), [".pkgmeta", "Core.lua"])
        self.assertEqual(release_check.check_git(self.addon, "1.2.0", allow_dirty=True).status, "WARN")

    def test_both_test_naming_styles_and_no_harnesses(self):
        for name in ("test_a.lua", "b_test.lua", "wow.lua", "party-harness.lua", "transport-libs.lua"):
            (self.addon / "tests" / name).write_text("")
        (self.addon / "tests" / "hammercore").mkdir()
        (self.addon / "tests" / "hammercore" / "wow.lua").write_text("")
        self.assertEqual(release_check.lua_tests(self.addon), ["tests/b_test.lua", "tests/test_a.lua"])

    def test_lua_runs_in_the_container_from_the_addon_root(self):
        command = release_check.lua_command(self.addon, "tests/test_a.lua", None)
        self.assertEqual(command[:2], ["docker", "run"])
        self.assertIn(f"{self.addon}:/w", command)
        self.assertEqual(command[-3:], ["nickblah/lua:5.1-alpine", "lua", "tests/test_a.lua"])
        self.assertEqual(release_check.lua_command(self.addon, "tests/test_a.lua", "lua5.1"),
                         ["lua5.1", "tests/test_a.lua"])

    def test_lua_failures_are_listed(self):
        # A stand-in interpreter: fails any test that mentions boom.
        lua = self.temp / "fake-lua"
        lua.write_text('#!/bin/sh\nif grep -q boom "$1"; then echo "$1:1: boom" >&2; exit 1; fi\n')
        lua.chmod(0o755)
        (self.addon / "tests" / "test_good.lua").write_text("assert(true)\n")
        (self.addon / "tests" / "bad_test.lua").write_text("error('boom')\n")
        result = release_check.check_lua(self.addon, "1.2.0", str(lua))
        self.assertEqual(result.status, "FAIL")
        self.assertEqual(result.reason, "1 of 2 Lua tests failed")
        self.assertEqual(result.details, ["tests/bad_test.lua: tests/bad_test.lua:1: boom"])

    def test_python_tests_run_when_present(self):
        self.assertEqual(release_check.check_python(self.addon, "1.2.0").status, "SKIP")
        (self.addon / "tests" / "test_ok.py").write_text("print('fine')\n")
        self.assertEqual(release_check.check_python(self.addon, "1.2.0").status, "PASS")
        (self.addon / "tests" / "test_bad.py").write_text("raise SystemExit('broken')\n")
        result = release_check.check_python(self.addon, "1.2.0")
        self.assertEqual(result.status, "FAIL")
        self.assertIn("broken", result.details[0])

    def test_every_step_runs_after_a_failure(self):
        (self.addon / "Core.lua").write_text("local x = 2\n")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = release_check.main([str(self.addon), "--version", "v1.2.0", "--skip-tests"])
        lines = out.getvalue().splitlines()
        self.assertEqual(code, 1)
        self.assertEqual(lines[0], "Release check: Demo 1.2.0")
        steps = [line.split()[1] for line in lines[1:-1] if line[:4].strip() in ("PASS", "FAIL", "WARN", "SKIP")]
        self.assertEqual(steps, ["toc", "version", "whatsnew", "hammercore", "lua", "python", "changelog", "git"])
        # No vendored HammerCore, and Core.lua is dirty: both reported, nothing else hidden.
        self.assertTrue(any(line.startswith("FAIL hammercore") for line in lines))
        self.assertTrue(any(line.startswith("FAIL git") for line in lines))
        self.assertTrue(any(line.startswith("PASS changelog") for line in lines))
        self.assertEqual(lines[-1], "FAIL")


if __name__ == "__main__":
    unittest.main()
