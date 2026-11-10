# Changelog

All notable changes to HammerCore are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and HammerCore uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.1] - 2026-11-11

### Added

- **GitHub link in the settings footer.** Next to CurseForge, for addons
  whose TOC `## X-Website` points at GitHub, with a new `GitHub.tga` icon.
- **What's new links can open a tab.** An item with `tab = "Cells"` next to
  its `page` opens that settings page on that tab.

## [0.5.0] - 2026-11-10

HammerCore 0.5.0, which includes the unreleased 0.4.0 work.

### Added

- **Flights.** `HC.Flights` tracks flight paths for addons that pass
  `flights = true` to `HC:Init`: takeoff and landing callbacks, the flight
  in progress with its time left, and estimates on the flight map. Times
  are learned per route and shared by every flights addon through the
  `ConsecratedHammerFlights` global, with LibTaxiData's leg lengths as the
  first estimate. Diagnostics gain a Flights section, and Troubleshooting a
  Flight times section with a **Get LibTaxiData** link.
- `check.py` fails a flights addon that doesn't declare LibTaxiData, as
  required or optional, in its TOCs and `.pkgmeta`.
- **Minimap menu.** Right-clicking the minimap button opens a small menu:
  settings, Profiles, then the addon's own extras from `minimap.menu`.
  Prefer the old way? "Minimap right-click" on Visibility switches it back
  to opening settings.
- **Settings search.** Lost a setting? The search box at the top of the
  settings window finds it and takes you straight there. "Settings search"
  on Visibility hides it.
- **Welcome window.** `HC.Welcome` gives an addon a one-page setup window
  with a banner and a row of choices per setting. New installs see every
  row, updates only the new ones. It replaces that login's What's new popup,
  stays out of combat, and comes with `setup`, "Setup on new features" and
  **Run setup again**.
- Flights picked from NPC chat (no flight map, so no `TakeTaxiNode`) are
  caught: control loss starts a 10-second watch for taxi state, and once the
  world has loaded a light check every 2 seconds catches anything else. They
  take off with no route or estimate, and a reload mid-flight still resumes
  rather than counting as a new takeoff. Diagnostics show the taxi state.
- Addons can watch takeoff and landing without LibTaxiData
  (`flights = { estimates = false }`).
- `tools/release_check.py` runs every release check and prints one PASS or
  FAIL. `tools/status.py` reports what's parked across every addon and can
  write the wiki's Addon status page.
- Diagnostics show the minimap right-click mode and the welcome state.
- Question IDs are now permanent: `data/quiz/ids.txt` lists every shipped
  ID, `generate_quiz.py --check` fails if one goes missing, and
  `"retired": true` drops a question while keeping its ID reserved.

### Changed

- Settings search now sits beside the page's preview button above the tabs.
  The description keeps clear of both controls, and hiding search gives its
  space back.
- `check.py` ignores Lua comments when looking for `flights`, and doesn't
  ask for LibTaxiData when estimates are off.

## [0.3.2] - 2026-11-10

### Changed

- **Profiles are the whole layout.** Every declared group is saved per
  profile; players no longer choose. The "Included in profiles" section is
  gone. On load, a group a player had left shared joins every profile with
  the value in use. `Profiles:SetIncluded` and the group `default` field are
  gone; `Profiles:Included` is true for every declared group.
- **Profile tag.** Shows "Profile: <name>" on every main page; click for
  Profiles. `spec.profileGroups` and `spec.profilePartial` are no longer used.
  `Profiles:PageStatus()` returns just the active profile.

- **Reload UI** is no longer in the settings footer. `HC.Settings:
  RequestReload(reason)` shows it, with the reason as its hint, when a change
  really needs a reload. The theme picker keeps its own Reload to apply.

### Added

- `HC.Settings:Focus(page, setting)` opens a page, scrolls to the row with
  that label and pulses it twice. `UI.SettingLink(panel, y, text, page,
  setting)` is a link that does it. Rows register their label as they're
  built (`UI.RegisterRow`).
- `HC.spec.visibilityMinimap(panel, y)`: addon rows right under Show minimap
  button on Visibility.

## [0.3.1] - 2026-11-09

### Added

- `spec.bulk` on `UI.MultiSelect`: **Select all** and **Deselect all** links
  across the top of the menu, as in Blizzard's filter menus. `true` sets every
  tickable item; a function(selected) lets the addon do it its own way.

## [0.3.0] - 2026-11-09

### Added

- **Profile tag.** Every main settings page shows the active profile beside
  its title, and whether the page saves to it ("Saved to profile: Party") or
  is shared ("Shared by all profiles (active: Party)"). Pages name their
  groups with `spec.profileGroups`; `spec.profilePartial` notes that the rest
  of the page is shared. Clicking it opens Profiles. `Profiles:PageStatus`.
- **Multi-select profile rules.** A rule's Group and Where are sets, picked
  with the new `UI.CompactMultiSelect`; none or all ticked means any. Older
  single-value rules still match and describe.
- `UI.Header(panel, text, y, icon)` takes an optional icon (texture, file ID
  or a function re-read on refresh).
- Link dialogs show the whole URL, led by the addon's logo with a badge for
  the destination (`HC.Dialog:Link{ icon = "CurseForge.tga" }`).

### Changed

- A two-column row's centre rule only shows once a right-hand cell joins it.
- `tools/check.py` checks subfolders of the vendored copy (such as
  `Textures`), not just its top level.

- **New settings shell.** The rail keeps its place, with a brand block, a
  header band with the page title and description, optional tabs across the
  top (`spec.tabs = {{ name, build, columns }}`), and a footer with Reload UI,
  support links and Close. A Window scale slider (0.7 to 1.3) sits in the
  header and is saved per account.
- **Two-column grid.** Settings pages lay rows out two to a line in
  alternating stripes by default (reference pages stay single); `spec.columns`
  or `UI.Columns(panel, count, y)` changes it, and `UI.Flush` closes a half
  row. `spec.pinned` adds an area above every tab, and `UI.ActionButton`
  lines a page action up with the page reset.
  Checkboxes become `UI.Switch` toggles (Classic keeps its checkboxes), and
  sliders, dropdowns and inputs sit on the right of their row.
- **`UI.Link`**, an underlined text link. `UI.PageLink` and What's new use it
  in place of buttons.
- **`HC.Bindings`.** A shared Key Bindings page: pick an item from a pool on
  the right, press a key, mouse button or wheel, and it joins the bound list
  on the left with its key and a remove button. `HC.Bindings.Capture` is the
  themed "press a key" prompt on its own. A `bind` that refuses a key can
  return a replace function too, and the prompt shows **Replace**.
- **Support links.** Discord and Buy me a coffee in the footer, which copy
  their link through `HC.Dialog:Link`. `spec.links` overrides them, `false`
  hides them, and **Show support links** on Visibility turns them off.
- Textures for the new look (Circle, Fade, Chevron, Discord, Coffee) in
  `Textures/`.
- `spec.headerAction = { text, onClick, hint }` puts a page's own button
  in the header (Salve's Show live preview), `HC.spec.onSettingsShown` runs
  when settings open, and `UI.CloseButton` is the header's X for an
  addon's own windows.
- A CurseForge link leads the support links for any addon whose TOC has
  `## X-CurseForge: <url>`.
- The profile selector drops its own "Profile" title (pages put it under a
  Profile heading), so the dropdown comes first.
- `tools/stage.py` stages Forever builds to the live client's folder
  (`wow-forever-interface`) now that WoW Forever is out of beta.

- **Profiles.** `HC.Profiles` gives an addon named profiles for groups of
  its settings, with a standard Profiles page, a Profile selector for other
  pages, a quick-switch menu and a `profile [name]` command. Players choose
  which settings belong to profiles, start new ones from the active profile
  or the defaults, and can keep a profile per character. Switches wait for
  combat to end.
- **Auto-switch.** Optional profile switching when the group or instance
  changes, by first-match rules (group type, size range, instance type and
  instance or group size). It can switch straight away or ask first, and the
  triggers, prompt and manual-pick behaviour are all settings. Off by
  default.
- **What's new page.** Addons with highlights get a What's new page at the
  top of REFERENCE listing every release with its date, each release in its own card, plus a quest-style "!" on
  its rail button until the player opens it after an update (**Mark unread
  What's new** on Visibility turns it off). About's What's new button opens
  the page. Opening it swaps the "!" for the turn-in "?" with the quest
  turn-in sound (**Turn-in sound** on Visibility). `whatsnew reset` steps the
  record back a release for testing, and `whatsnew sound` plays the turn-in
  and reports which sound the client accepted. Releases can carry `date` and `history = true`; history entries
  sit under Earlier releases and never pop up after an update.
- `tools/whatsnew_check.py` fails a release whose version, or any earlier
  release since the addon adopted What's new, has no What's new entry.
- `HC.Dialog` (themed confirm and text prompts), `HC.Menu` (a small click
  menu) and two compact controls, `UI.CompactSelect` and `UI.Stepper`.

- **What's new.** An addon that supplies `spec.whatsNew` gets a small window
  of release highlights the first time the player logs in after an update.
  It stays quiet on a fresh install and for releases without highlights,
  waits for combat to end, and counts `-devN` builds as their base version.
  A highlight can open a settings page, and highlights sharing a page share
  one button. A highlight added to a release already seen shows on its own.
  When several addons have news after an update, it all shows
  in one window with a section per addon. Players turn it off with **Show
  what's new after updates** on Visibility, and reopen it with `whatsnew`
  or the About page's **What's new** button.

- `tools/discord_dev.py`, and `stage.py --discord`, post a staged dev build
  to the Discord dev-builds channel, packaging only the clients just staged.
- Curated quiz additions with stable IDs, source URLs, client applicability,
  multiple category tags and easier/hard difficulty. The bank is split into
  generated category files with JSONL source and freshness checks.
- Six solo quiz result lines per score, retaining the original lines and
  avoiding consecutive repeats for the same score during a login session.

### Fixed

- Solo question selection now retains the class and race tokens returned by
  the client, allowing matching class and race questions into the draw.
- The minimap button's first normal click after a drag is no longer swallowed
  on clients that do not emit a click when a drag ends.

### Changed

- Quiz sharing: Say and Party are secure macro buttons, so one click posts
  `/s` or `/p` with the result as the player's own macro; addon code
  calling the chat API was blocked on WoW Forever. Share is disabled in
  combat and during a keystone, PvP match or encounter (Midnight's addon
  restrictions), and Party is disabled when you are not in a group.

### Changed

- The Theme page and `theme` command are withdrawn, and Classic is switched
  off until it is reworked. A saved Classic choice falls back to Modern. The
  Classic code stays and is still built by the tests.
- Select buttons and menu items never wrap. `UI.Dropdown` takes an optional
  button width for long choices.

### Added

- **Classic theme**, Blizzard's own look circa 2004, chosen on the Theme
  page or with `/<cmd> theme classic` and applied after a reload:
  - windows (settings, reports, quiz) wear the dialog-box frame;
  - cards, rows, selects and menus use tooltip borders;
  - buttons are the red UIPanel buttons;
  - checkboxes and sliders use Blizzard's checkbox and slider-bar art;
  - headings and accents are gold.

  Borderless fills stay flat, so layouts are unchanged.

### Fixed

- Clicking the tick in a multi-select menu now chooses it; before, only the
  label responded.
- The first rail heading lines up with the page title.

### Added

- `UI.DynamicDropdown` (choices re-read on open) and `UI.DropdownPair` (two
  labelled selects under one heading), ported from Salve.

- A lore quiz behind a quest-giver "!" on every About page, and
  `/<cmd> quiz`: five questions from a shared library of more than 100,
  with four shuffled choices, an 8-second timer, a verdict in chat and a
  saved best score. Questions are tagged by era (both, Classic for WoW
  Forever, or Retail) and optionally by class or race, so a character only
  sees questions that fit their world and themselves. The hidden
  `/<cmd> quiz timer <3-30|off>` changes the timer.

### Changed

- Visibility puts the addon's own sections first, then "Other" with
  "Show minimap button" and "Show startup message", matching Salve.
- About has one centred, whimsical layout for every addon: the note
  heading, the addon icon as a button with a caption, and a rotating tip in
  a storybook face. The icon shows a new tip and prints to chat.

### Added

- Multi-select items may have function labels and a `disabled` state,
  re-read each time the menu opens.
- A `flavour` theme colour for whimsical copy.

- `Commands:AddAction` lists non-command actions, such as mouse clicks, in
  help and on the Commands page.
- `panel.hcCreatePinned(height)` keeps a live preview above a page's
  scrolling content.
- `UI.PageReset` restores one page's settings.
- A legacy key can be `{ key = "old", invert = true }` for settings stored
  the other way round.

- `UI.SearchPicker` for large searchable lists and `UI.TextInput` for
  single-line text.
- `spec.railButton` pins one action, such as a live preview, to the foot of
  the settings rail.
- An invalid saved settings-window position is discarded instead of used.
- `spec.hideInCombat` hides settings, reports and the minimap button in
  combat, and refuses to open settings until combat ends.

- Shared settings window with a CORE section, a divider and a REFERENCE
  section, plus standard Visibility, Theme, Commands, Troubleshooting and
  About pages.
- Theme tokens for every colour and surface. Modern is available; Classic is
  registered but not yet built.
- Settings controls: check, slider, dropdown, multi-select, button, header,
  section label, text, card and page link.
- Command framework: the core commands, the shared `toggle`/`lock`/`unlock`
  verbs, addon commands in named sections, grouped `help`, and a Commands
  page generated from the same table.
- Gold chat prefix, the standard login message, a minimap button and a
  copyable diagnostics window.
- Tools: `sync.py` (vendor and pin), `check.py` (drift check),
  `toc_check.py`, `stage.py` (both clients) and `new_addon.py` (scaffold).
