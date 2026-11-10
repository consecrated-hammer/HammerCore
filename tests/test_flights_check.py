#!/usr/bin/env python3
"""check.py's rule that a flights addon declares LibTaxiData."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("hc_check", ROOT / "tools" / "check.py")
check = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check)

GOOD_PKGMETA = """package-as: Demo

required-dependencies:
  - libtaxidata

ignore:
  - tests
"""


def addon(temp: Path, core: str, tocs: dict[str, str], pkgmeta: str | None) -> Path:
    root = temp / "Demo"
    (root / "Libs" / "HammerCore").mkdir(parents=True)
    (root / "Core.lua").write_text(core)
    # Lines in vendored code and tests never count.
    (root / "Libs" / "HammerCore" / "Core.lua").write_text("-- flights = true in a comment")
    for name, text in tocs.items():
        (root / name).write_text(text)
    if pkgmeta is not None:
        (root / ".pkgmeta").write_text(pkgmeta)
    return root


class FlightDependencyTest(unittest.TestCase):
    def test_addon_without_flights_needs_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = addon(Path(temp), "HC:Init({ name = 'Demo' })", {"Demo.toc": "## Title: Demo\n"}, None)
            self.assertEqual(check.flight_problems(root), [])

    def test_declared_everywhere_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            tocs = {"Demo.toc": "## Dependencies: LibTaxiData\n",
                    "Demo_Camelot.toc": "## RequiredDeps: Foo, LibTaxiData\n"}
            root = addon(Path(temp), "HC:Init({ flights = true })", tocs, GOOD_PKGMETA)
            self.assertEqual(check.flight_problems(root), [])

    def test_optional_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            tocs = {"Demo.toc": "## OptionalDeps: LibTaxiData\n", "Demo_Camelot.toc": "## OptionalDeps: LibTaxiData\n"}
            pkgmeta = "optional-dependencies:\n  - libtaxidata\n"
            root = addon(Path(temp), "HC:Init({ flights = true })", tocs, pkgmeta)
            self.assertEqual(check.flight_problems(root), [])

    def test_missing_declarations_fail(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            tocs = {"Demo.toc": "## Dependencies: LibTaxiData\n", "Demo_Camelot.toc": "## Notes: none\n"}
            pkgmeta = "embedded-libraries:\n  - libtaxidata\n"
            root = addon(Path(temp), "HC:Init({ flights = true })", tocs, pkgmeta)
            problems = check.flight_problems(root)
            self.assertEqual(len(problems), 2)
            self.assertIn("Demo_Camelot.toc", problems[0])
            self.assertIn(".pkgmeta", problems[1])

    def test_no_estimates_needs_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            core = "HC:Init({\n    name = 'Demo',\n    flights = { estimates = false },\n})"
            root = addon(Path(temp), core, {"Demo.toc": "## Title: Demo\n"}, None)
            self.assertEqual(check.flight_problems(root), [])

    def test_table_with_estimates_needs_the_library(self) -> None:
        for core in ("HC:Init({ flights = {} })", "HC:Init({ flights = { estimates = true } })"):
            with tempfile.TemporaryDirectory() as temp:
                root = addon(Path(temp), core, {"Demo.toc": "## Title: Demo\n"}, None)
                self.assertEqual(len(check.flight_problems(root)), 2, core)

    def test_commented_flights_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = addon(Path(temp), "-- flights = true is for later\nHC:Init({})", {"Demo.toc": "## Title: Demo\n"}, None)
            self.assertEqual(check.flight_problems(root), [])

    def test_needs_library(self) -> None:
        self.assertTrue(check.needs_library("flights = true"))
        self.assertTrue(check.needs_library("flights = { }"))
        self.assertTrue(check.needs_library("flights={estimates=true}"))
        self.assertFalse(check.needs_library("flights = {\n  estimates = false, -- hide only\n}"))
        self.assertFalse(check.needs_library("flights = false"))
        self.assertFalse(check.needs_library("-- flights = true"))


if __name__ == "__main__":
    unittest.main()
