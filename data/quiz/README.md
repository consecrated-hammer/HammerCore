# Shared trivia data

Edit the JSONL here, then run `python3 tools/generate_quiz.py` from HammerCore.
`--check` checks the schema and proves the generated category Lua files are current.
The runtime loads all category files, with each question stored once. Selecting
several tags cannot duplicate a question in a hosted game.

Generated category Lua files pack each complete row with lightweight seeded
byte obfuscation. `src/QuizData.lua` decodes the rows at load time. Questions,
choices, IDs and source links are not readable strings in those shipped files.
This deters casual file browsing, not extraction by a determined reader. Keep
editing the readable JSONL here; do not edit the packed output. Staging excludes
this directory. The cross-language round-trip check proves all decoded fields
match their canonical source, including UTF-8 and category tags.

Each row has a stable `id`, `question`, `correct`, three `wrong` answers, an
explicit `era`, `difficulty`, `categories` and direct `source` URL. Optional
`class` and `race` tokens preserve the solo quiz's character filters. Hosted
Loreforge games use all selected topics regardless of the host's character.

`both` means shared lore or mechanics suitable for both supported clients.
`classic` means **WoW Forever**, not generic Classic or Wrath. `retail` also
covers questions explicitly framed as historical Retail content. Forever talent
questions use Blizzard's Forever class deep dives; older Classic mechanics are
not evidence that the same mechanic applies to Forever. Retail tooltip facts
were captured on 2026-10-23 and may need revision after patches.

`legacy.jsonl` preserves the original 117 questions and their repository
provenance. The remaining batches use source-page facts and short boss-quote
excerpts gathered for this expansion. Atlas entries ask about the named NPC,
place or historical encounter rather than treating the encounter as currently
available. Difficulty is an editorial judgement. A source URL records where to
check a fact; schema tests cannot prove that every answer remains correct.

Keep exactly one defensible correct answer. Check aliases, renamed locations,
multiple encounter appearances, changed allegiances and historical scope before
adding distractors. Quote excerpts stay short; the generator caps cumulative
quoted question text at 25 words per source page across all batches. Write
questions in original wording rather than copying descriptions or tooltips.

The 2026-10-24 bank contains 1,000 questions: 360 shared, 139 Forever-only and
501 Retail-only; 692 easier and 308 hard. Category counts overlap:

| Category | Total | Forever eligible | Retail eligible |
| --- | ---: | ---: | ---: |
| General lore | 432 | 210 | 399 |
| Geography | 340 | 184 | 302 |
| Classes and mechanics | 181 | 75 | 142 |
| Races | 186 | 106 | 167 |
| Boss quotes | 103 | 30 | 90 |
| Hallow's End | 16 | 1 | 16 |
| Famous Last Words | 39 | 1 | 38 |
| Murlocs and Mischief | 21 | 9 | 21 |
| Dubious Goblin Engineering | 34 | 8 | 32 |
| Things You Probably Vendored | 59 | 11 | 51 |

Do not tag Headless Horseman dungeon mechanics as Forever content without
evidence that Forever actually implements them. The shared Hallow's End entry
is general festival lore.
