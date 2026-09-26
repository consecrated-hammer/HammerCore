# Changelog

All notable changes to HammerCore are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and HammerCore uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Clicking the tick in a multi-select menu now chooses it; before, only the
  label responded.
- The first rail heading lines up with the page title.

### Added

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
