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
Questions in Smaller Holidays use IDs beginning with `holidays-<event>-`.
Loreforge's `Seasons.lua` lists the event keys and uses them to put each
question in season with its own holiday.

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

The 2026-11-19 bank contains 2,320 questions. There are 670 shared,
182 Forever-only and 1,468 Retail-only. There are 1,530 easier questions
and 790 hard questions. Category counts overlap.

| Category | Total | Forever eligible | Retail eligible |
| --- | ---: | ---: | ---: |
| General lore | 455 | 225 | 422 |
| Geography | 399 | 209 | 361 |
| Classes and mechanics | 183 | 75 | 144 |
| Races | 194 | 107 | 175 |
| Hallow's End | 66 | 6 | 61 |
| Boss quotes | 132 | 36 | 119 |
| Famous Last Words | 67 | 7 | 66 |
| Murlocs and Mischief | 62 | 27 | 60 |
| Dubious Goblin Engineering | 65 | 19 | 63 |
| Things You Probably Vendored | 112 | 32 | 102 |
| Mount Up | 69 | 9 | 69 |
| Pets and Pet Battles | 117 | 19 | 117 |
| Professions and Recipes | 65 | 39 | 49 |
| Easter Eggs and Pop Culture | 68 | 14 | 68 |
| Quests That Ruined Your Day | 53 | 14 | 43 |
| Gnomes and Their Poor Decisions | 52 | 25 | 52 |
| Dragons | 54 | 23 | 54 |
| Hearth and Home | 55 | 29 | 55 |
| Feast of Winter Veil | 53 | 24 | 53 |
| Lunar Festival | 100 | 64 | 100 |
| Love is in the Air | 53 | 2 | 53 |
| Noblegarden | 88 | 7 | 88 |
| Children's Week | 58 | 9 | 58 |
| Midsummer Fire Festival | 53 | 5 | 51 |
| Brewfest | 56 | 0 | 56 |
| Pilgrim's Bounty | 77 | 0 | 77 |
| Darkmoon Faire | 64 | 18 | 58 |
| Smaller Holidays | 75 | 10 | 75 |

Do not tag Headless Horseman dungeon mechanics as Forever content without
evidence that Forever actually implements them. The shared Hallow's End entry
is general festival lore.
