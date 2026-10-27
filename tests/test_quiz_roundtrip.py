#!/usr/bin/env python3
"""Compare every decoded Lua field with canonical JSONL, including UTF-8.

Run with Lua 5.1 on PATH, or --emit to run the resulting Lua script elsewhere.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def script():
    lines = [
        'package.path = "./tests/?.lua;" .. package.path',
        'local wow = require("wow")',
        'wow.Install({TestAddon = {Version = "1"}})',
        'local before = os.clock()',
        'local ns = wow.LoadHammerCore("src", "TestAddon")',
        'local byId = {}',
        'for _, row in ipairs(ns.HammerCore.QUIZ) do byId[row.id] = row end',
        'local function check(actual, expected) assert(actual == expected, "decoded field differs from source") end',
    ]
    count = 0
    literal = lambda value: json.dumps(value, ensure_ascii=False)
    for path in sorted((ROOT / 'data/quiz').glob('*.jsonl')):
        for line in path.read_text().splitlines():
            if not line.strip():
                continue
            row = json.loads(line)
            count += 1
            lines.append('do local row = assert(byId[' + literal(row['id']) + '])')
            for index, value in enumerate([row['question'], row['correct'], *row['wrong']], 1):
                lines.append(f'check(row[{index}], {literal(value)})')
            for key in ('id', 'era', 'difficulty', 'class', 'race', 'source'):
                lines.append(f'check(row.{key}, {literal(row[key]) if row.get(key) is not None else "nil"})')
            lines.append('check(table.concat(row.categories, ","), ' + literal(','.join(row['categories'])) + ') end')
    lines.append(f'check(#ns.HammerCore.QUIZ, {count})')
    lines.append(f'io.write("{count} decoded questions match canonical source; load CPU seconds: " .. (os.clock() - before) .. "\\n")')
    return '\n'.join(lines) + '\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emit', action='store_true')
    args = parser.parse_args()
    if args.emit:
        print(script(), end='')
    else:
        lua = shutil.which('lua5.1') or shutil.which('lua')
        assert lua, 'Lua 5.1 is required (or use --emit)'
        subprocess.run([lua, '-'], input=script(), text=True, cwd=ROOT, check=True)
