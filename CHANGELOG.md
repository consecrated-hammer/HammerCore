# Changelog

All notable changes to HammerCore are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and HammerCore uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
