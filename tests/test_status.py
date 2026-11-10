#!/usr/bin/env python3
"""tools/status.py against fake addon repositories in a temp folder."""

from __future__ import annotations

import contextlib
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import status  # noqa: E402

GIT_ENV = {**os.environ, "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.invalid",
           "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.invalid"}

DESCRIPTIONS = """# CurseForge description maintenance

| Addon | Description | Released source checked | Paste status |
|---|---|---|---|
| Alpha | [Alpha.md](descriptions/Alpha.md) | v1.0.0 | Pasted (reported 2026-11-10) |
| Beta | [Beta.md](descriptions/Beta.md) | v2.0.0 | Updated for unreleased 2.1.0; paste when 2.1.0 ships |

Other text.
"""


def git(repo: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, text=True,
                          env=GIT_ENV).stdout.strip()


def commit_all(repo: Path, message: str = "commit") -> str:
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", message)
    return git(repo, "rev-parse", "HEAD")


class StatusTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.temp)
        self.root = self.temp / "addons"
        self.wiki = self.temp / "wiki"
        (self.wiki / "curseforge").mkdir(parents=True)
        (self.wiki / "curseforge" / "description-maintenance.md").write_text(DESCRIPTIONS)
        self.retail, self.forever = self.temp / "retail", self.temp / "forever"
        self.clients = {"retail": (self.retail, "{name}.toc"), "forever": (self.forever, "{name}_Camelot.toc")}

        hammercore = self.root / "HammerCore"
        (hammercore / "src").mkdir(parents=True)
        (hammercore / "src" / "Core.lua").write_text('HC.VERSION = "0.4.0"\n')
        git(hammercore, "init", "-q")
        self.pin = commit_all(hammercore)

        # Alpha: current HammerCore, pushed, one dev build staged in each client.
        alpha = self.addon("Alpha", "0.4.0", self.pin, "## [Unreleased]\n\n## [1.0.0] - 2026-11-01\n")
        self.remote(alpha)
        for folder, toc in ((self.retail, "Alpha.toc"), (self.forever, "Alpha_Camelot.toc")):
            (folder / "Alpha").mkdir(parents=True)
            (folder / "Alpha" / toc).write_text("## Version: 1.0.0-dev3\n")

        # Beta: old HammerCore, unreleased notes, a commit not pushed and a dirty file. Forever only.
        beta = self.addon("Beta", "0.3.0", self.pin, "## [Unreleased]\n\n- New thing.\n\n## [2.0.0] - 2026-11-01\n",
                          tocs=("Beta_Camelot.toc",))
        self.remote(beta)
        (beta / "New.lua").write_text("")
        commit_all(beta, "unpushed")
        (beta / "Dirty.lua").write_text("")

        # Not addons: no TOC, or no git.
        (self.root / "Assets").mkdir()
        git(self.root / "Assets", "init", "-q")
        (self.root / "Loose").mkdir()
        (self.root / "Loose" / "Loose.toc").write_text("## Version: 1\n")

    def addon(self, name: str, hc: str, pin: str, changelog: str,
              tocs: tuple[str, ...] = ()) -> Path:
        repo = self.root / name
        (repo / "Libs" / "HammerCore").mkdir(parents=True)
        (repo / "Libs" / "HammerCore" / "VERSION").write_text(f"version={hc}\ncommit={pin}\n")
        for toc in tocs or (f"{name}.toc", f"{name}_Camelot.toc"):
            (repo / toc).write_text("## Version: " + ("1.0.0" if name == "Alpha" else "2.0.0") + "\n")
        (repo / "CHANGELOG.md").write_text("# Changelog\n\n" + changelog)
        git(repo, "init", "-q", "-b", "main")
        commit_all(repo)
        return repo

    def remote(self, repo: Path) -> None:
        bare = self.temp / f"{repo.name}.git"
        subprocess.run(["git", "init", "-q", "--bare", str(bare)], check=True, capture_output=True)
        git(repo, "remote", "add", "origin", str(bare))
        git(repo, "push", "-q", "-u", "origin", "main")

    def report(self) -> dict[str, status.Status]:
        return {row.name: row for row in status.collect(self.root, self.wiki, self.clients)}

    def test_discovers_git_repos_with_a_toc_and_hammercore(self):
        self.assertEqual([path.name for path in status.discover(self.root)], ["Alpha", "Beta", "HammerCore"])

    def test_current_addon(self):
        alpha = self.report()["Alpha"]
        self.assertEqual((alpha.dirty, alpha.ahead), (0, 0))
        self.assertEqual(alpha.vendored, "0.4.0")
        self.assertIsNone(alpha.vendored_note)
        self.assertEqual(alpha.staged, {"retail": "1.0.0-dev3", "forever": "1.0.0-dev3"})
        self.assertEqual(alpha.unreleased, "empty")
        self.assertEqual(alpha.description, "pasted")

    def test_parked_addon(self):
        beta = self.report()["Beta"]
        self.assertEqual((beta.dirty, beta.ahead), (1, 1))
        self.assertEqual(beta.vendored_note, "vendored HammerCore 0.3.0, current 0.4.0")
        self.assertEqual(beta.staged, {"retail": "n/a", "forever": None})
        self.assertEqual(beta.unreleased, "notes")
        self.assertEqual(beta.description, "pending")

    def test_hammercore_without_upstream(self):
        hammercore = self.report()["HammerCore"]
        self.assertIsNone(hammercore.ahead)
        self.assertEqual(hammercore.vendored, "0.4.0")
        self.assertEqual(status.cells(hammercore)[2], "no upstream")
        self.assertEqual(hammercore.unreleased, "no changelog")

    def test_pin_behind_src_is_flagged(self):
        hammercore = self.root / "HammerCore"
        (hammercore / "src" / "New.lua").write_text("")
        commit_all(hammercore)
        self.assertIn("src/ has changed since", self.report()["Alpha"].vendored_note)
        (hammercore / "README.md").write_text("docs only\n")
        commit_all(hammercore)
        alpha = self.root / "Alpha" / "Libs" / "HammerCore" / "VERSION"
        alpha.write_text(f"version=0.4.0\ncommit={git(hammercore, 'rev-parse', 'HEAD~1')}\n")
        self.assertIsNone(self.report()["Alpha"].vendored_note, "a docs-only commit doesn't make a pin old")

    def test_paste_status_wording(self):
        self.assertFalse(status.pending("Description unchanged; pasted (reported 2026-10-28)"))
        self.assertTrue(status.pending("Paste when 1.2.0 ships"))
        self.assertTrue(status.pending("Not pasted yet"))

    def test_attention_list(self):
        items = status.attention(list(self.report().values()))
        self.assertIn("Beta: 1 commit(s) not pushed", items)
        self.assertIn("Beta: CHANGELOG [Unreleased] has notes", items)
        self.assertTrue(any(item.startswith("Beta: CurseForge description waiting") for item in items))
        self.assertFalse(any(item.startswith("Alpha") for item in items))

    def test_page(self):
        now = datetime(2026, 11, 10, 14, 30, tzinfo=timezone.utc)
        text = status.page(list(self.report().values()), self.root, self.wiki, self.clients, now)
        self.assertTrue(text.startswith("---\ntype: status\nstatus: active\nverified:\n"))
        self.assertIn('  at: "2026-11-10T14:30:00+00:00"', text)
        self.assertIn("stale_after: 2026-11-17", text)
        self.assertIn(f"  - resource: {self.root / 'Alpha'}", text)
        self.assertIn("\n# Addon status\n", text)
        self.assertIn("| Beta | 1 | 1 | 0.3.0 (old) | 2.0.0 | n/a | - | notes | pending |", text)
        self.assertIn("## Needs attention", text)
        self.assertNotIn("—", text)

    def test_write_only_with_flag(self):
        args = ["--root", str(self.root), "--wiki", str(self.wiki),
                "--retail", str(self.retail), "--forever", str(self.forever)]
        with contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(status.main(args), 0)
        self.assertIn("Alpha", out.getvalue())
        self.assertFalse((self.wiki / "addon-status.md").exists())
        with contextlib.redirect_stdout(io.StringIO()):
            status.main(args + ["--write"])
        self.assertIn("# Addon status", (self.wiki / "addon-status.md").read_text())


if __name__ == "__main__":
    unittest.main()
