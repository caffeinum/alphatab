# alphatab

An app switcher for macOS ordered **A–Z, not by recency** — plus the rest of a
hyperkey setup built on [skhd](https://github.com/koekeishiya/skhd).

⌘tab cycles most-recently-used. That order changes after every switch, so the
same app is never the same number of presses away twice and you can never build
muscle memory for it. `alphatab` sorts alphabetically instead: for a given set
of running apps, an app is always exactly where it was last time.

<!-- screenshot goes here -->

```
  ChatGPT             ⇪G
* cmux                ⇪C
→ Finder
  Granola
  Helium              ⇪H ⇪2
  Messages            ⇪I
  Superconductor      ⇪S
```

Each row shows that app's own direct shortcut, read live out of your `skhdrc`.
The switcher is the escape hatch — the badges are there to teach you the key
that skips it. Apps with no badge are the ones that actually need it.

## What's in here

| | |
|---|---|
| `alphatab` | the switcher: a resident daemon and its HUD |
| `helium-raise` | per-profile run-or-raise for Helium / any Chromium |
| `skhd-cheatsheet` | renders your `skhdrc` as a keyboard diagram |
| `examples/skhdrc` | the config all three are wired into |

skhd itself is **not** bundled — install it separately:

```sh
brew install koekeishiya/formulae/skhd
skhd --start-service
```

## Install

```sh
git clone https://github.com/caffeinum/alphatab
cd alphatab
make install          # builds to ~/.local/bin, loads the LaunchAgent
```

Then bind it in `~/.config/skhd/skhdrc`:

```
ctrl + alt + shift + cmd - d : ~/.local/bin/alphatab next
ctrl + alt + shift + cmd - a : ~/.local/bin/alphatab prev
```

`examples/skhdrc` puts everything in one 3x4 block under the left hand, right
next to caps lock — spatial memory rather than mnemonics, with `a`/`d` flanking
`s` like movement keys:

```
1 helium·you   2 helium·2027    3 cheatsheet
q chatgpt      w safari         e superhuman
a prev app     s superconductor d next app
z telegram     x messages       c cmux
```

`make uninstall` removes the binaries and unloads the agent.

### The hyperkey

These bindings assume caps lock is remapped to `ctrl+alt+shift+cmd` — a
combination no application uses, so it never collides with anything. Raycast
does this under Settings → Advanced → Hyper Key; so do Karabiner-Elements and
[hyperkey](https://hyperkey.app).

## Usage

```sh
alphatab next          # advance the selection (what you bind)
alphatab prev
alphatab next --dry    # print the cycle to stdout, switch nothing
alphatab daemon        # run the resident daemon (launchd does this for you)
```

| env | default | |
|---|---|---|
| `ALPHATAB_DWELL` | `0.5` | seconds the HUD lingers after the last press |
| `ALPHATAB_SKHDRC` | `~/.config/skhd/skhdrc` | where to read shortcut badges from |
| `ALPHATAB_DEBUG` | unset | timing marks on stderr |

The HUD stays up for as long as the hyperkey is held, like ⌘tab's switcher, and
`ALPHATAB_DWELL` is the floor for a quick tap.

## How it works, and why

**It's a daemon.** skhd spawns a fresh process per keypress. The obvious
implementation — draw a panel, sleep, exit — means holding the hyperkey and
tapping `j` three times tears the panel down and rebuilds it three times, which
reads as a flash. So the first press starts a resident daemon holding one panel
it shows and hides, and every later press does nothing but `SIGUSR1` it and exit.
A keypress costs ~10ms.

**It watches the modifier, not the key.** skhd reports the press and never the
release, so there's no keyup to hang the dismissal off. The daemon polls
`NSEvent.modifierFlags` at 25Hz instead and hides once the hyperkey is released.

**It sits above the menu bar.** `NSRunningApplication.activate()` is
asynchronous — the app you switched to brings its windows forward a beat after
the panel is drawn. At a normal window level those windows land on top of it.
The panel is `.screenSaver` level and re-asserts front while visible.

**It uses the name on the `.app`.** `localizedName` returns the bundle name,
which is not always the name you know an app by — Superconductor.app reports
itself as `super.engineering`. The Finder name is the recognisable one.

### helium-raise

Chromium exposes no way to raise a *specific profile's* window. `open -b` just
activates the app and raises whatever was focused last, ignoring profiles;
`--profile-directory` always spawns a brand new window. The profile appears in
exactly one place visible from outside the process — the window title, as
`<tab> - <App> - <profile>` — so `helium-raise` reads the profile's display name
out of `Local State`, walks the app's windows over the accessibility API, and
raises the one that matches. It only launches when there isn't one.

```sh
helium-raise "Default"
helium-raise "Profile 1"
```

Needs accessibility permission, which it inherits from whatever spawns it — so
grant it to skhd under Privacy & Security → Accessibility.

### skhd-cheatsheet

Renders your hyperkey bindings as an ANSI keyboard with the bound keys lit and
labelled. Generated from `skhdrc` at runtime, so it can't drift out of date —
rebind something and the new key lights up on its own.

```sh
skhd-cheatsheet        # writes html and opens it
```

Set `CHEATSHEET_BROWSER` to a bundle id to pin which browser it opens in.

## Prior art

The run-or-raise idea comes from [Will Harris's
note](https://www.willharris.dev/garden/run-or-raise), which is Linux/`wmctrl`
and explicitly doesn't cover multiple windows or browser profiles. This is the
macOS half of that, plus the parts it punts on.

## License

MIT
