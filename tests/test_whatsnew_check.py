#!/usr/bin/env python3
"""tools/whatsnew_check.py: every release from the first entry needs one."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import whatsnew_check  # noqa: E402

CHANGELOG = """# Changelog

## [Unreleased]

## [1.3.0] - 2026-11-09

## [1.2.1-beta] - 2026-11-05

## [1.2.0] - 2026-11-01

## [1.1.0] - 2026-10-01
"""


class WhatsNewCheckTests(unittest.TestCase):
    def addon(self, entries: str, changelog: str = CHANGELOG) -> Path:
        root = Path(tempfile.mkdtemp())
        (root / "CHANGELOG.md").write_text(changelog, encoding="utf-8")
        (root / "Core").mkdir()
        (root / "Core" / "WhatsNew.lua").write_text(entries, encoding="utf-8")
        # Entries inside the vendored library or tests never count.
        (root / "Libs").mkdir()
        (root / "Libs" / "Fake.lua").write_text('{ version = "1.3.0", items = {} }', encoding="utf-8")
        return root

    def test_complete_history_passes(self):
        addon = self.addon('ns.W = { { version = "1.3.0", items = {} }, { version = "1.2.1", items = {} },\n'
                           '{ version = "1.2.0", items = {} } }')
        self.assertEqual(whatsnew_check.check(addon), [])

    def test_releases_before_adoption_are_not_required(self):
        addon = self.addon('{ version = "1.3.0", items = {} }, { version = "1.2.1", items = {} },'
                           '{ version = "1.2.0", items = {} }')
        self.assertNotIn("1.1.0", " ".join(whatsnew_check.check(addon)))

    def test_missed_releases_fail_and_beta_counts_as_base(self):
        addon = self.addon('{ version = "1.3.0", items = {} }, { version = "1.2.0", items = {} }')
        self.assertEqual(whatsnew_check.check(addon), [f"{addon.name}: no What's new entry for 1.2.1"])

    def test_the_tagged_release_needs_an_entry(self):
        addon = self.addon('{ version = "1.3.0", items = {} }, { version = "1.2.1", items = {} },'
                           '{ version = "1.2.0", items = {} }')
        self.assertEqual(whatsnew_check.check(addon, "v1.4.0"), [f"{addon.name}: no What's new entry for 1.4.0"])
        self.assertEqual(whatsnew_check.check(addon, "1.3.0-beta"), [])

    def test_history_entries_do_not_move_the_start_back(self):
        addon = self.addon('{ version = "1.3.0", date = "2026-11-09", items = {} },'
                           '{ version = "1.2.1", items = {} }, { version = "1.2.0", items = {} },'
                           '{ version = "1.1.0", date = "2026-10-01", history = true, items = {} }')
        self.assertEqual(whatsnew_check.check(addon), [])
        older = self.addon('{ version = "1.3.0", items = {} }, { version = "1.1.0", items = {} }')
        self.assertEqual(len(whatsnew_check.check(older)), 2, "a normal old entry requires the releases after it")

    def test_an_addon_without_highlights_fails(self):
        addon = self.addon("-- nothing here")
        self.assertIn("no What's new highlights", whatsnew_check.check(addon)[0])


if __name__ == "__main__":
    unittest.main()
