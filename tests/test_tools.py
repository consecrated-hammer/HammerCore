#!/usr/bin/env python3
"""End-to-end check of the scaffold, vendoring, drift check and staging.

Needs a committed HammerCore checkout (sync pins HEAD) and a Lua 5.1
interpreter on PATH as `lua5.1` or `lua`.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"


def run(*args: str, cwd: Path | None = None, expect: int = 0) -> str:
    result = subprocess.run(list(args), cwd=cwd, capture_output=True, text=True)
    if result.returncode != expect:
        raise AssertionError(f"{' '.join(args)} exited {result.returncode}, expected {expect}\n"
                             f"{result.stdout}{result.stderr}")
    return result.stdout


def main() -> int:
    lua = shutil.which("lua5.1") or shutil.which("lua")
    assert lua, "a Lua 5.1 interpreter is required"
    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)
        addon = temp / "Anvilwise"
        run(sys.executable, str(TOOLS / "new_addon.py"), "Anvilwise", "--command", "anvil", "--dest", str(addon))

        for expected in ["Anvilwise.toc", "Anvilwise_Camelot.toc", "Core.lua", "Options.lua",
                         "Libs/HammerCore/HammerCore.xml", "Libs/HammerCore/VERSION",
                         "tests/hammercore/wow.lua", "tests/test_anvilwise.lua",
                         ".github/workflows/lint.yml", ".github/workflows/release.yml",
                         ".pkgmeta", "LICENSE.txt", "CHANGELOG.md"]:
            assert (addon / expected).is_file(), f"scaffold is missing {expected}"
        release = (addon / ".github/workflows/release.yml").read_text()
        assert "Anvilwise.toc Anvilwise_Camelot.toc" in release, "release workflow names both TOCs"
        assert "{{" not in (addon / "Core.lua").read_text(), "placeholders are filled"

        print(run(lua, "tests/test_anvilwise.lua", cwd=addon).strip())
        run(sys.executable, str(TOOLS / "toc_check.py"), str(addon))
        run(sys.executable, str(TOOLS / "check.py"), str(addon))

        core = addon / "Libs/HammerCore/Core.lua"
        core.write_text(core.read_text() + "\n-- hand edit\n")
        out = run(sys.executable, str(TOOLS / "check.py"), str(addon), expect=1)
        assert "modified Core.lua" in out, "a hand edit to the vendored copy is caught"
        stray = addon / "Stray.lua"
        stray.write_text("local x = 1\n")
        out = run(sys.executable, str(TOOLS / "toc_check.py"), str(addon), expect=1)
        assert "does not load Stray.lua" in out, "an unlisted Lua file is caught"
        stray.unlink()

        output = temp / "AddOns"
        first = run(sys.executable, str(TOOLS / "stage.py"), str(addon), "--client", "retail", "--output", str(output))
        second = run(sys.executable, str(TOOLS / "stage.py"), str(addon), "--client", "retail", "--output", str(output))
        assert "0.1.0-dev1" in first and "0.1.0-dev2" in second, "staging increments the dev version"
        staged = output / "Anvilwise"
        assert "## Version: 0.1.0-dev2" in (staged / "Anvilwise.toc").read_text()
        assert "## Version: 0.1.0\n" in (staged / "Anvilwise_Camelot.toc").read_text(), "only the client's TOC is stamped"
        assert (staged / "Libs/HammerCore/Core.lua").is_file(), "the vendored library ships"
        assert not (staged / "tests").exists(), "tests do not ship"

        # An interrupted swap leaves only the set-aside copy; the number must
        # still climb rather than restart at dev1.
        staged.rename(output / ".Anvilwise.previous")
        third = run(sys.executable, str(TOOLS / "stage.py"), str(addon), "--client", "retail", "--output", str(output))
        assert "0.1.0-dev3" in third, "an interrupted swap does not reset the dev number"
    print("hammercore tool tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
