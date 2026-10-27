# HammerCore

The shared foundation for Consecrated Hammer's World of Warcraft addons:
Salve, CheckMark, Speedster, HammerLink and Buffsmith. It gives each addon
the same settings window, theme, commands, chat style, startup message,
minimap button and reference pages, so they feel like one family.

HammerCore is **not** an addon and is **not** installed by players. Each
addon vendors a pinned copy under `Libs/HammerCore/` and loads it into its
own private namespace, with no global and no LibStub. Five addons can each
run a different HammerCore version without affecting one another.

## Starting a new addon

```sh
python3 tools/new_addon.py Anvilwise --command anvil
```

The scaffold contains:

- Retail and Forever TOCs;
- HammerCore vendored and wired in;
- one example page and one command;
- a test, Lint and a guarded Release workflow;
- `.pkgmeta`, a changelog and the GPL licence.

Add `Textures/Anvilwise.tga`, run the test, commit, then create the GitHub
repository.

## Using it in an addon

List the library first in both TOCs:

```
Libs\HammerCore\HammerCore.xml
Core.lua
```

Declare the addon, add its pages and commands, then start HammerCore once
saved variables are loaded:

```lua
local addonName, ns = ...
local HC, UI = ns.HammerCore, ns.HammerCore.UI

HC:Init({
    name = "Anvilwise", command = "anvil", aliases = { "aw" },
    savedVariable = "AnvilwiseDB",
    db = function() return ns.db end,
    icon = "Interface\\AddOns\\Anvilwise\\Textures\\Anvilwise",
    legacy = { startupMessage = "showStartupMessage" },  -- old keys to adopt
    diagnostics = function() return "report text" end,
    status = function() return "status text" end,
    about = { note = "NOTE", tips = { "..." }, credit = "..." },
    minimap = { rightClick = fn, rightClickLabel = "lock" },
    -- Optional leftClick / leftClickLabel override the default settings click.
    toggle = { help = "Show or hide the frame", run = fn },
    resetPosition = fn,
    railButton = { label = fn, run = fn, active = fn },  -- optional rail action
    hideInCombat = true,                                  -- optional
})

HC.Commands:Add({ name = "scan", section = "Bags", help = "Rescan bags", run = fn })
HC.Settings:NewPage({ name = "General" }, function(panel, y)
    _, y = UI.Check(panel, "Enabled", "Hint.", y, get, set)
    return y
end)

-- in ADDON_LOADED, after ns.db exists:
HC:Start()
```

### What every addon gets

| Area | Standard |
|---|---|
| Chat | `Name:` prefix in `|cffd4af37`; `HC.Print(message)` |
| Login | `Name v1.2.3 loaded - type /cmd for settings, /cmd help for commands` |
| Core commands | `/cmd`, `help`, `version`, `about`, `debug`, `startup [on\|off]`, `minimap [on\|off]`, `reset position`, `reset settings`, `quiz` (hidden: `theme`, `quiz timer`) |
| Shared verbs | `toggle`, `lock`, `unlock`, present only when the addon supplies them |
| Settings rail | Addon pages under CORE, a divider, then REFERENCE: addon reference pages, Commands, Troubleshooting, About (Theme is withheld for now) |
| Visibility | "Show startup message" and "Show minimap button", plus `spec.visibility(panel, y)`. The page goes last in CORE unless placed with `HC.Settings:AddVisibility()` |

HammerCore keeps its state in `db.hammerCore`, and on first run adopts the
keys named in `spec.legacy`. `reset settings` clears `spec.savedVariable`
and reloads, unless the addon supplies `spec.resetSettings`.

### Controls

`HC.UI` provides `Check`, `Slider`, `Dropdown`, `MultiSelect`,
`SearchPicker`, `TextInput`, `Button`,
`SelectButton`, `Header`, `SectionLabel`, `Text`, `Card`, `PageLink`,
`AttachHint` and `ShowColourPicker`. Each builder takes `(panel, ..., y)`
and returns the control and the next `y`.

Every colour goes through `HC.Theme` roles (`T.Surface`, `T.Fill`,
`T.Text`, `T.Code`), never literal values. Settings text is one line and
does not wrap.

### Lore quiz

`src/QuizData.lua` initialises and decodes the shared question library. Each decoded entry is
`{ "Question", "Correct", "Wrong", "Wrong", "Wrong", era = ?, class = ?, race = ? }`,
with the correct answer always second. `era` is `"both"` (the default),
`"classic"` (WoW Forever) or `"retail"`. `class` and `race` take client
tokens such as `PALADIN` or `Draenei`. The client's era comes from
`spec.clientLabel` (anything containing "Forever" is Classic), or from
`spec.era`. `tests/test_quiz.lua` validates every entry.

The pool is split into generated `src/Quiz_<category>.lua` files, loaded
after `QuizData.lua` initialises the shared table. Curated source rows live in
`data/quiz/*.jsonl`; run `python3 tools/generate_quiz.py` after editing them,
or `--check` to verify the generated files are current. Each added row keeps
a stable ID, source URL, explicit client tag, difficulty and one or more
category tags. An entry appears once even when several categories match.
`classic` specifically means WoW Forever, not every Classic-derived client.

Generated category files use lightweight seeded byte obfuscation to discourage
casual peeking at questions and answers. They decode when the library loads,
without a bit library or external dependency. This is not secure encryption;
the decoder and data are both present on the client. Readable JSONL is maintainer
source and is excluded from client staging. `tests/test_quiz_roundtrip.py`
compares every decoded field with that source under Lua 5.1.

Loreforge uses these tags for hosted games without filtering by the host's
class or race. The solo quiz still uses the character filters. It now has six
result lines per score, chosen once when a run ends; repeating a score avoids
the previous line for that score during the current login session.

### Themes

**The Theme page and `theme` command are withdrawn for now**, and Classic is
switched off (`available = false`) until it is reworked. Tests switch it on
to keep it building. When enabled, the two themes are chosen per addon on the
Theme page and applied after a reload:

- **Modern**, the flat slate look Salve introduced.
- **Classic**, Blizzard's look circa 2004: dialog-framed windows,
  tooltip-bordered cards, red panel buttons, the classic checkbox and
  slider, and gold headings.

A theme is a colour table plus optional `surfaces`: framed backdrops keyed
by background role, used for bordered panels. `UI.Button`,
`UI.CheckButton` and `UI.Slider` switch to Blizzard templates and art under
Classic. Everything else follows from the colour roles.

## Tools

| Tool | Purpose |
|---|---|
| `tools/sync.py <addon>` | Vendor `src/` into `<addon>/Libs/HammerCore`, pinned to HEAD (commit first) |
| `tools/check.py <addon>` | Fail if the vendored copy differs from its pinned commit |
| `tools/toc_check.py <addon>` | Fail if a TOC does not load exactly the addon's Lua files, following XML |
| `tools/stage.py <addon>` | Stage `-devN` builds into the Retail and Forever client folders. Add `--discord [--note TEXT]` to post the zip too |
| `tools/discord_dev.py <addon>` | Zip the staged dev build and post it to the Discord dev-builds channel (`DEV_BUILDS_WEBHOOK_URL` in the host automation env). `--dry-run DIR` builds without posting |
| `tools/new_addon.py <Name>` | Scaffold a new addon |

Never edit an addon's `Libs/HammerCore` directly. Change HammerCore, test,
commit, then run `sync.py`. Addon CI runs `check.py`.

## Tests

```sh
docker run --rm -v "$PWD:/r" -w /r nickblah/lua:5.1-alpine lua tests/test_core.lua
python3 tests/test_tools.py   # needs lua5.1 and a committed checkout
```

`tests/wow.lua` is a small headless WoW API. It is vendored into each addon
as `tests/hammercore/wow.lua` for its own tests.

## Licence

GPL v3. See [LICENSE.txt](LICENSE.txt).
