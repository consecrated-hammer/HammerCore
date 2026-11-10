#!/usr/bin/env python3
"""Validate curated quiz JSONL and render the category Lua files. No network access."""
import argparse
import collections
import json
import hashlib
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / 'data/quiz/ids.txt'
LEDGER_HEADER = ('# Every question ID that has shipped. Never remove or reuse a line: Loreforge\n'
                 '# picks the daily question from these IDs, so they must stay stable. Retire a\n'
                 '# bad question with "retired": true instead of deleting it.\n')
CATEGORIES = {'lore', 'geography', 'class', 'race', 'hallowsend', 'bossquotes', 'lastwords', 'murlocs', 'goblins', 'items'}
CLASSES = set('WARRIOR PALADIN HUNTER ROGUE PRIEST DEATHKNIGHT SHAMAN MAGE WARLOCK MONK DRUID DEMONHUNTER EVOKER'.split())
RACES = set('Human Dwarf NightElf Gnome Draenei Worgen Pandaren Orc Scourge Tauren Troll BloodElf Goblin VoidElf LightforgedDraenei DarkIronDwarf KulTiran Mechagnome Nightborne HighmountainTauren MagharOrc ZandalariTroll Vulpera Dracthyr EarthenDwarf'.split())


def quote(value):
    return json.dumps(value, ensure_ascii=False)


def pack(row):
    """Casual-peeking deterrent, not cryptographic protection. Lua decodes on load."""
    fields = [row['question'], row['correct'], *row['wrong'], row['id'], row['era'], row['difficulty'],
              row.get('class') or '', row.get('race') or '', row['source'], ','.join(row['categories'])]
    payload = b''.join(str(len(value.encode('utf-8'))).encode('ascii') + b':' + value.encode('utf-8') for value in fields)
    seed = int.from_bytes(hashlib.sha256(row['id'].encode()).digest()[:3], 'big') % 65521
    state, encoded = seed, bytearray()
    for value in payload:
        state = (state * 73 + 41) % 65521
        encoded.append((value + state % 256) % 256)
    return seed, encoded.hex()


def validate(rows):
    ids, questions = set(), {}
    quoted_words = collections.Counter()
    for row in rows:
        assert isinstance(row, dict), 'question row must be an object'
        required = {'id', 'question', 'correct', 'wrong', 'era', 'difficulty', 'categories', 'source'}
        assert required <= row.keys(), f'missing fields: {sorted(required - row.keys())}'
        key = row['id']
        for field in ('id', 'question', 'correct', 'era', 'difficulty', 'source'):
            assert isinstance(row[field], str), f'{key}: {field} must be text'
        assert isinstance(row['wrong'], list) and all(isinstance(s, str) for s in row['wrong']), f'{key}: wrong must be a list of text'
        assert isinstance(row['categories'], list) and all(isinstance(s, str) for s in row['categories']), f'{key}: categories must be a list of text'
        assert re.fullmatch(r'[a-z][a-z0-9-]+', key) and key not in ids, f'duplicate/invalid id {key}'
        ids.add(key)
        qkey = re.sub(r'[^a-z0-9]', '', row['question'].lower())
        for earlier in questions.get(qkey, []):
            same_client = row['era'] == earlier['era'] or 'both' in (row['era'], earlier['era'])
            same_class = not row.get('class') or not earlier.get('class') or row['class'] == earlier['class']
            same_race = not row.get('race') or not earlier.get('race') or row['race'] == earlier['race']
            assert not (same_client and same_class and same_race), f'duplicate question {key}'
        questions.setdefault(qkey, []).append(row)
        assert row['era'] in {'both', 'classic', 'retail'}, key
        assert isinstance(row.get('retired', False), bool), f'{key}: retired must be true or false'
        assert row['difficulty'] in {'easy', 'hard'}, key
        assert row['categories'] and len(set(row['categories'])) == len(row['categories']), key
        assert set(row['categories']) <= CATEGORIES, key
        assert row.get('class') is None or row['class'] in CLASSES, key
        assert row.get('race') is None or row['race'] in RACES, key
        assert row['source'].startswith(('https://', 'http://')), key
        answers = [row['correct'], *row['wrong']]
        assert len(answers) == 4 and len({s.casefold().strip() for s in answers}) == 4, key
        for text in [row['question'], *answers]:
            assert isinstance(text, str) and text.strip() == text and text, key
            assert not any(ord(c) < 32 or c == '|' for c in text), f'chat control character: {key}'
        assert len(row['question']) <= 140 and max(map(len, answers)) <= 80, key
        url = urlsplit(row['source'])
        page = (url.netloc.lower(), unquote(url.path))
        for excerpt in re.findall(r'["“]([^"“”]+)["”]', row['question']):
            quoted_words[page] += len(excerpt.split())
        assert quoted_words[page] <= 25, f'quoted excerpts exceed 25 words for source {row["source"]}'


def render(rows):
    groups = collections.defaultdict(list)
    for row in rows:
        if row.get('retired'):
            continue
        groups[row['categories'][0]].append(row)
    files = {}
    for category in sorted(CATEGORIES):
        lines = ['-- Generated by tools/generate_quiz.py from data/quiz/*.jsonl.',
                 '-- Packed to discourage casual peeking. This is not secure encryption.',
                 'local _, ns = ...', 'local bank = ns.HammerCore.QUIZ', 'for _, packed in ipairs({']
        for row in groups[category]:
            seed, encoded = pack(row)
            lines.append('    { ' + str(seed) + ', "' + encoded + '" },')
        lines += ['}) do bank[#bank + 1] = ns.HammerCore.DecodeQuiz(packed[1], packed[2]) end', '']
        files[ROOT / ('src/Quiz_' + category + '.lua')] = '\n'.join(lines)
    return files


def read_ledger(path=LEDGER):
    if not path.exists():
        return []
    return [line.strip() for line in path.read_text().splitlines()
            if line.strip() and not line.startswith('#')]


def ledger_problems(rows, ledger):
    """Shipped IDs that vanished, and IDs not yet recorded."""
    ids = {row['id'] for row in rows}
    shipped = set(ledger)
    missing = sorted(shipped - ids)
    new = sorted(ids - shipped)
    return missing, new


def write_ledger(ledger, new, path=LEDGER):
    path.write_text(LEDGER_HEADER + ''.join(key + '\n' for key in [*ledger, *new]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    rows = []
    for path in sorted((ROOT / 'data/quiz').glob('*.jsonl')):
        rows.extend(json.loads(line) for line in path.read_text().splitlines() if line.strip())
    validate(rows)
    ledger = read_ledger()
    missing, new = ledger_problems(rows, ledger)
    assert not missing, ('shipped question IDs are missing (retire them with "retired": true '
                         'instead of deleting or renaming): ' + ', '.join(missing))
    if args.check:
        assert not new, 'question IDs not in data/quiz/ids.txt (run tools/generate_quiz.py): ' + ', '.join(new)
    elif new or not LEDGER.exists():
        write_ledger(ledger, new)
    for path, text in render(rows).items():
        if args.check:
            assert path.exists() and path.read_text() == text, f'stale generated file {path}'
        else:
            path.write_text(text)
    retired = sum(1 for row in rows if row.get('retired'))
    print(f'{len(rows)} total questions validated ({retired} retired)')
    print('Client tags:', dict(collections.Counter(row['era'] for row in rows)))
    print('Difficulty:', dict(collections.Counter(row['difficulty'] for row in rows)))
    print('Categories:', dict(collections.Counter(tag for row in rows for tag in row['categories'])))
    return 0


if __name__ == '__main__':
    sys.exit(main())
