#!/usr/bin/env python3
"""cf_description.py compares live CurseForge Markdown with the wiki file
after CurseForge's own rewrites, so normalise() must treat them as equal."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from cf_description import normalise, sent_text_matches  # noqa: E402

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
# The save request carries rendered HTML; every Markdown URL must be in it.
md = "[![Badge](https://img.shields.io/x?a=1&b=2)](https://example.com/p) [link](https://new.example/)"
html = '{"description": "<a href=\\"https://example.com/p\\"><img src=\\"https://img.shields.io/x?a=1&amp;b=2\\"></a> <a href=\\"https://new.example/\\">link</a>", "descriptionType": 1}'
assert sent_text_matches(html, md)
assert not sent_text_matches(html.replace("new.example", "old.example"), md)
assert not sent_text_matches("not json", md)
assert not sent_text_matches(None, md)
print("cf_description tests passed")
