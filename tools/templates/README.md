# {{NAME}}

**One-line pitch: what it does, in plain words.**

_Optional flourish line._

[![Discord](https://img.shields.io/badge/discord-join-5865F2?style=flat-square&logo=discord&logoColor=white)](https://discord.gg/z3xKxRygDc) [![Retail](https://img.shields.io/badge/retail-supported-4c9a7a?style=flat-square)](https://www.curseforge.com/wow/addons/{{SLUG}}) [![WoW Forever](https://img.shields.io/badge/wow%20forever-supported-4c9a7a?style=flat-square)](https://www.curseforge.com/wow/addons/{{SLUG}}) [![Release](https://img.shields.io/github/v/release/consecrated-hammer/{{NAME}}?style=flat-square&color=4c9a7a&label=release)](https://github.com/consecrated-hammer/{{NAME}}/releases) [![License](https://img.shields.io/badge/license-GPL--3.0-4c9a7a?style=flat-square)](https://github.com/consecrated-hammer/{{NAME}}/blob/main/LICENSE.txt)

Questions, bugs or ideas? Come say hi on the [Consecrated Hammer Discord](https://discord.gg/z3xKxRygDc). Bug reports go in `#bug-reports`, or you can open a [GitHub issue](https://github.com/consecrated-hammer/{{NAME}}/issues).

---

A short paragraph on what {{NAME}} does and who it's for.

## What it does

- Four to six feature bullets, no implementation detail.

## Getting started

Install, then type `/{{COMMAND}}` for settings.

## Commands

| Command | What it does |
| --- | --- |
| `/{{COMMAND}}` | Open settings |

Every Consecrated Hammer addon also has `help`, `version`, `about`, `debug`, `startup`, `minimap`, `reset settings` and `quiz`.

## Limits

- What it deliberately doesn't or can't do.

## Screenshots

Optional. Use absolute image URLs (forgecdn or GitHub) so they work on CurseForge too.

## Licence

GPL v3, see [LICENSE.txt](https://github.com/consecrated-hammer/{{NAME}}/blob/main/LICENSE.txt).

## Development

Everything above this heading is also the CurseForge description; paste it into the author console when it changes.

- Settings, commands, the minimap button, the startup message and the
  Commands, Troubleshooting and About pages come from HammerCore,
  vendored under `Libs/HammerCore`. Never edit that copy: change HammerCore,
  commit, then run `python3 ../HammerCore/tools/sync.py .`.
- Add artwork at `Textures/{{NAME}}.tga` (TGA or BLP; WoW cannot load PNG).
- Stage both clients with `python3 ../HammerCore/tools/stage.py .`.
- Releases are tagged from `main` only.
