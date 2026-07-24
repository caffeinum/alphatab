# alphatab

Alphabetical macOS app switcher + the skhd hyperkey kit around it.
skhd is a documented prerequisite, never vendored.

## Layout
- `src/alphatab.swift` — resident daemon + HUD. One panel, shown/hidden.
- `src/helium-raise.swift` — per-profile run-or-raise via the accessibility API.
- `scripts/skhd-cheatsheet.sh` — renders skhdrc as a keyboard diagram.
- `examples/skhdrc` — reference config, paths point at `~/.local/bin`.
- `launchd/agent.plist.in` — `@LABEL@`/`@BIN@` substituted by `make agent`.

## Build
`make install` builds to `~/.local/bin` and (re)loads the LaunchAgent.
`make restart` after changing the daemon — the running one won't pick up edits.

## Non-obvious constraints
- A panel per keypress flashes; skhd spawns a process per press, so later
  presses must signal the daemon instead of drawing.
- No keyup event exists from skhd — dismissal polls `NSEvent.modifierFlags`.
- `activate()` is async, so the panel must sit at `.screenSaver` level and
  re-assert front, or the activated app's windows cover it.
- Use the `.app` filename for display, not `localizedName` (Superconductor.app
  reports `super.engineering`).
- Spotlight indexing may be off — resolve bundle ids by scanning Info.plists,
  never `mdfind`.
