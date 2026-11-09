# HammerCore

The shared foundation for Consecrated Hammer's World of Warcraft addons:
Salve, CheckMark, Speedster, HammerLink and Buffsmith. It gives each addon
the same settings window, theme, commands, chat style, startup message,
minimap button and reference pages, so they feel like one family.

HammerCore is **not** an addon and is **not** installed by players. Each
addon vendors a pinned copy under `Libs/HammerCore/` and loads it into its
own private namespace, with no LibStub and only one small global, for the
shared What's new window. Five addons can each run a different HammerCore
version without affecting one another.

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
    whatsNew = {                                          -- optional
        { version = "1.4.0", items = {
            { text = "Anvils now shine.", page = "General" },  -- page adds a button
        } },
    },
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
| Core commands | `/cmd`, `help`, `version`, `about`, `debug`, `startup [on\|off]`, `minimap [on\|off]`, `reset position`, `reset settings`, `quiz`, plus `whatsnew [reset\|sound]` with `spec.whatsNew` (hidden: `theme`, `quiz timer`) |
| Shared verbs | `toggle`, `lock`, `unlock`, present only when the addon supplies them |
| Settings rail | Addon pages under CORE, a divider, then REFERENCE: addon reference pages, Commands, Troubleshooting, About (Theme is withheld for now) |
| Visibility | "Show startup message" and "Show minimap button", plus `spec.visibility(panel, y)`. The page goes last in CORE unless placed with `HC.Settings:AddVisibility()` |

With `spec.whatsNew`, the first login after an update opens a short list of
the highlights for every release newer than the one the player last saw. A
fresh install records the version silently, releases without highlights never
open it, combat delays it, and `-devN` counts as its base version. An existing
profile with no record (an update from before What's new) sees only the
current release. A highlight added to a release the player has already seen
shows on its own, so dev builds pick up each new highlight. Highlights that
open the same page share one button.
Players get `whatsnew`, a Visibility toggle and an About button, which show
only that addon.

After an update, every Consecrated Hammer addon with news shares one window,
"What's new in Consecrated Hammer addons", with a section per addon. It's the
one place HammerCore copies share anything: each copy leaves its unseen
highlights in the `ConsecratedHammerWhatsNew` global at login, the first timer
to fire draws them all with the newest renderer loaded, and each addon still
records what it has seen in its own saved variables. Keep the highlight shape
stable, since an older copy may draw a newer addon's entries.

The same highlights fill a **What's new** page at the top of REFERENCE, newest
first, each release in its own card, with a quest-style "!" on its rail button until the player opens it after an update
(**Mark unread What's new** on Visibility). A release can add
`date = "2026-11-08"` and `history = true`. History entries are highlights
written after the fact: the page lists them under Earlier releases, the popup
never shows them, and `whatsnew_check.py` doesn't require entries for every
patch around them.

HammerCore keeps its state in `db.hammerCore`, and on first run adopts the
keys named in `spec.legacy`. `reset settings` clears `spec.savedVariable`
and reloads, unless the addon supplies `spec.resetSettings`.

### Controls

`HC.UI` provides `Check`, `Switch`, `Link`, `CellAction`, `Slider`, `Dropdown`, `MultiSelect`,
`SearchPicker`, `TextInput`, `Button`,
`SelectButton`, `Header`, `SectionLabel`, `Text`, `Card`, `PageLink`,
`AttachHint` and `ShowColourPicker`. Each builder takes `(panel, ..., y)`
and returns the control and the next `y`. `CompactSelect` and `Stepper`
take `(parent, label, hint, x, y, ...)` instead, for cards and
multi-column rows: a small title above a select, or a number with `-` and
`+` (shift-click steps by 5).

The window has a rail (brand, pages, version), a header band with the page
title, description, Window scale (0.7 to 1.3) and close button, and a footer
with Reload UI, support links and Close. Pages can split into tabs across
the header with `spec.tabs = {{ name = "...", build = fn, columns = 2 }}`,
and `spec.pinned = { height, build(frame) }` adds an area above every tab,
such as a live preview the tabs share. Settings pages lay rows out two to a
line in alternating stripes; reference pages stay single column, and
`spec.columns = 1` (or `UI.Columns(panel, 1, y)`) opts a page or section
out. `UI.Flush(panel, y)` closes a half-filled row;
headers, text and cards flush for you. `Check` draws a `UI.Switch` toggle
(Classic keeps the checkbox), `UI.CellAction(row, text, width, hint)` adds a
small button inside a switch row, `UI.ActionButton(panel, y, text, onClick)`
puts a page action on its own line in line with the page reset, and `UI.Link(parent, text, onClick)` is an
underlined text link.

Support links come from `HC.Settings.LINKS` (Discord and Buy me a coffee), led
by the addon's CurseForge page when its TOC has `## X-CurseForge: <url>`.
`spec.links` replaces them and `false` hides them; players can hide them with
**Show support links** on Visibility. Clicking one opens `HC.Dialog:Link`, a
read-only box with the URL selected for Ctrl+C.

A page can add `headerAction = { text = string or fn, onClick, hint }` for its
own button in the header, and `HC.spec.onSettingsShown` runs when settings
open. `UI.CloseButton(parent, onClick, size)` is the header's X.

`HC.Bindings.Page(panel, y, spec)` is the shared Key Bindings page: bound
items on the left with their key and a remove button, the pool on the right
as sections of tiles. The spec supplies `pool()` (sections of
`{ title, items, empty? }`, items `{ id, name, icon, detail? }`), `bound()`
(`{ id, name, icon, key }`), `bind(item, key)` (return `false, message` to
refuse, or `false, message, replace` to also offer a **Replace** button that
calls `replace()`), `unbind(id)`, and optionally `clearAll`, `inputs`
(`{ keys, mouse, wheel }`), `label`, `tooltip`, `empty`, `poolTitle` and
`poolHint`. `HC.Bindings.Capture:Start(spec)` is the "press a key" prompt on
its own, and `HC.Bindings.Label(key)` turns `SHIFT-BUTTON4` into
"Shift+Mouse 4".

`HC.Dialog:Confirm(spec)` and `HC.Dialog:Prompt(spec)` are themed yes/no
and one-line text dialogs. They're plain frames rather than StaticPopups,
work in combat, and close with Escape (which counts as cancel). A prompt's
`onAccept(text)` can return a string to keep it open and show that error.
`HC.Menu:Open(items, anchor?)` opens a small click menu at the cursor or
under a frame; items are `{ text, checked?, disabled?, title?, func? }` or
`{ separator = true }`.

### Profiles

`HC.Profiles:Setup(spec)` gives an addon named profiles for groups of its
settings, plus optional auto-switching by group and instance. The addon
keeps reading its own flat keys: the values there always belong to the
loaded profile, and a switch captures them back before loading the next
one, then calls `spec.apply(name, reason)` so the addon can redraw.

```lua
HC.Profiles:Setup({
    groups = { { key = "position", label = "Position", keys = { "point" }, default = true } },
    defaults = function() return ns.defaults end,
    seed = { { name = "Party", values = { previewUnits = 5 } } }, active = "Party",
    rules = { { profile = "Party", min = 1, max = 5 } },   -- starter auto-switch rules
    apply = function(name, reason) redraw() end,
    unsafe = function() return InCombatLockdown() end,     -- switches wait while true
})
```

- Call `HC.Profiles:Ready()` once saved variables exist (in `ADDON_LOADED`,
  before `HC:Start()`). It repairs the saved shape, seeds the starter
  profiles the first time and loads this character's profile.
- Players choose which groups belong to profiles (`Included in profiles`).
  A group that's ticked out is shared by every profile.
- `HC.Profiles:NewPage({ extra = fn })` adds the standard Profiles page:
  management, Included in profiles, the addon's `extra` rows, then
  Auto-switch with editable rule cards. `HC.Profiles:Selector(panel, y)` is
  the Profile dropdown and Save as new button for the top of another page.
- `HC.Profiles:MenuItems()` returns menu items for quick switching, and
  Setup registers `/<cmd> profile [name]`.
- Auto-switch (off by default) is Off, Automatic or Ask first, with
  first-match rules on group type, size, instance type and whether size
  comes from the instance or the group. Which events trigger it, what a
  declined prompt does, prompting in combat and how long a manual pick
  holds are all settings. Everything lives in `db.hcProfiles`.

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

`whatsnew_check.py <addon> [--version X]` fails if a dated CHANGELOG release,
from the addon's first What's new entry onwards, has no `spec.whatsNew`
entry. With `--version` (the release tag) the version being released needs
one too. Every CurseForge release gets an entry, fixes included, so release
workflows run this before packaging.

## Tests

```sh
docker run --rm -v "$PWD:/r" -w /r nickblah/lua:5.1-alpine lua tests/test_core.lua
docker run --rm -v "$PWD:/r" -w /r nickblah/lua:5.1-alpine lua tests/test_profiles.lua
python3 tests/test_tools.py   # needs lua5.1 and a committed checkout
```

`tests/wow.lua` is a small headless WoW API. It is vendored into each addon
as `tests/hammercore/wow.lua` for its own tests.

## Licence

GPL v3. See [LICENSE.txt](LICENSE.txt).
