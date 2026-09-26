# {{NAME}}

Describe what {{NAME}} does.

Type `/{{COMMAND}}` for settings and `/{{COMMAND}} help` for every command.

## Development

- Settings, commands, the minimap button, the startup message and the
  Theme, Commands, Troubleshooting and About pages come from HammerCore,
  vendored under `Libs/HammerCore`. Never edit that copy: change HammerCore,
  commit, then run `python3 ../HammerCore/tools/sync.py .`.
- Add artwork at `Textures/{{NAME}}.tga` (TGA or BLP; WoW cannot load PNG).
- Stage both clients with `python3 ../HammerCore/tools/stage.py .`.
- Releases are tagged from `main` only.

## Licence

GPL v3. See [LICENSE.txt](LICENSE.txt).
