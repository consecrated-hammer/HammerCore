#!/usr/bin/env python3
"""cf_description.py compares live CurseForge Markdown with the wiki file
after CurseForge's own rewrites, so normalise() must treat them as equal."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from cf_description import normalise  # noqa: E402

# CurseForge's rewrites: bullets, wrapping, URL encoding, emphasis markers.
assert normalise("- one\n- two") == normalise("*   one\n*   two")
assert normalise("A line\nwrapped here.") == normalise("A line wrapped here.")
assert normalise("[x](<https://a b>)") == normalise("[x](https://a%20b)")
assert normalise("_hi_") == normalise("*hi*")
assert normalise("**bold**") == normalise("**bold**")
assert normalise("1. first") == normalise("1) first")
# Real changes still count.
assert normalise("banner 2113/775") != normalise("banner 2182/151")
assert normalise("**bold**") != normalise("_bold_")
print("cf_description tests passed")
