#!/bin/bash
# renders the current skhdrc hyperkey bindings as an html cheatsheet and opens it.
# generated from the config itself so it can never drift out of date.
set -euo pipefail

rc="${ALPHATAB_SKHDRC:-$HOME/.config/skhd/skhdrc}"
out="${TMPDIR:-/tmp}/skhd-cheatsheet.html"

# spotlight indexing is off on this machine, so mdfind can't resolve bundle
# ids — scan the app dirs' Info.plists once and build a lookup table instead.
bundle_index=$(
  for app in /Applications/*.app /System/Applications/*.app \
             /System/Applications/Utilities/*.app "$HOME/Applications"/*.app; do
    [ -d "$app" ] || continue
    id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null) || continue
    printf '%s\t%s\n' "$id" "$(basename "$app" .app)"
  done
)

app_name_for_bundle() {
  local name
  name=$(printf '%s' "$bundle_index" | awk -F'\t' -v id="$1" '$1==id{print $2; exit}')
  printf '%s' "${name:-$1}"
}

helium_profile_name() {
  /usr/bin/python3 - "$1" <<'PY' 2>/dev/null || printf '%s' "$1"
import json, sys
state = json.load(open(f"{__import__('os').path.expanduser('~')}/Library/Application Support/net.imput.helium/Local State"))
print(state["profile"]["info_cache"][sys.argv[1]]["name"])
PY
}

label_for() {
  local cmd="$1"
  case "$cmd" in
    *"open -b "*)
      app_name_for_bundle "$(printf '%s' "$cmd" | sed -E 's/.*open -b ([A-Za-z0-9._-]+).*/\1/')" ;;
    *helium-raise*)
      local dir
      dir=$(printf '%s' "$cmd" | sed -E 's/.*helium-raise "([^"]+)".*/\1/')
      printf 'Helium — %s' "$(helium_profile_name "$dir")" ;;
    *alphatab\ next*) printf 'next app' ;;
    *alphatab\ prev*) printf 'prev app' ;;
    *cheatsheet*) printf 'this cheatsheet' ;;
    *) printf '%s' "$cmd" ;;
  esac
}

key_label() {
  case "$1" in
    0x2C) printf '/' ;;
    *) printf '%s' "$1" ;;
  esac
}

# bound keys as "key<tab>label" — bash 3.2 on macOS has no associative arrays
bindings=$(
  grep -E '^ctrl \+ alt \+ shift \+ cmd - ' "$rc" | while IFS= read -r line; do
    key="${line%% :*}"; key="${key##*- }"
    cmd="${line#*: }"
    printf '%s\t%s\n' "$(key_label "$key")" "$(label_for "$cmd")"
  done
)

binding_for() {
  printf '%s' "$bindings" | awk -F'\t' -v k="$1" '$1==k{print $2; exit}'
}

# physical ansi layout. "width:cap" entries are the modifiers we draw but
# never bind — they're there so the rows line up like a real keyboard.
row1='` 1 2 3 4 5 6 7 8 9 0 - = 2:delete'
row2='1.5:tab q w e r t y u i o p [ ] 1.5:\'
row3='1.75:hyper a s d f g h j k l ; '"'"' 2.25:return'
row4='2.25:shift z x c v b n m , . / 2.25:shift'

render_row() {
  printf '<div class="row">'
  for cell in $1; do
    case "$cell" in
      *:*) width="${cell%%:*}"; key="${cell#*:}"; mod=1 ;;
      *)   width=1; key="$cell"; mod=0 ;;
    esac
    label=$(binding_for "$key")
    if [ "$key" = "hyper" ]; then
      printf '<div class="cap hyper" style="flex:%s"><span class="c">⇪</span><span class="l">hyper</span></div>' "$width"
    elif [ "$mod" = 1 ]; then
      printf '<div class="cap mod" style="flex:%s"><span class="c">%s</span></div>' "$width" "$key"
    elif [ -n "$label" ]; then
      printf '<div class="cap bound" style="flex:%s"><span class="c">%s</span><span class="l">%s</span></div>' \
        "$width" "$key" "$label"
    else
      printf '<div class="cap" style="flex:%s"><span class="c">%s</span></div>' "$width" "$key"
    fi
  done
  printf '</div>'
}

keyboard=$(for r in "$row1" "$row2" "$row3" "$row4"; do render_row "$r"; done)

cat > "$out" <<HTML
<!doctype html><meta charset="utf-8"><title>hyperkey cheatsheet</title>
<style>
:root{
  color-scheme:light dark;
  --line:color-mix(in srgb,currentColor 14%,transparent);
  --dim:color-mix(in srgb,currentColor 40%,transparent);
  --hit:#ff9500;
}
*{box-sizing:border-box}
body{font:16px/1.5 -apple-system,system-ui,sans-serif;max-width:60rem;margin:3.5rem auto;padding:0 1.5rem}
h1{font-size:1.35rem;margin:0 0 .2rem;letter-spacing:-.01em}
p.sub{opacity:.55;margin:0 0 2.2rem;font-size:.9rem}
.kb{display:flex;flex-direction:column;gap:.4rem}
.row{display:flex;gap:.4rem}
.cap{
  flex:1;min-width:0;aspect-ratio:1/.82;
  border:1px solid var(--line);border-radius:.5rem;
  display:flex;flex-direction:column;align-items:center;justify-content:center;gap:.15rem;
  padding:.2rem;
}
.cap .c{font:500 .85rem/1 ui-monospace,SFMono-Regular,monospace;color:var(--dim)}
.cap.mod .c{font-size:.6rem;letter-spacing:.04em;text-transform:uppercase}
.cap.bound{border-color:var(--hit);background:color-mix(in srgb,var(--hit) 12%,transparent)}
.cap.bound .c{color:var(--hit);font-weight:700;font-size:1rem}
.cap.bound .l{
  font-size:.58rem;line-height:1.15;text-align:center;
  overflow-wrap:anywhere;hyphens:auto;opacity:.85;
}
.cap.hyper{border-color:var(--dim);background:color-mix(in srgb,currentColor 7%,transparent)}
.cap.hyper .c{font-size:1rem;color:inherit}
.cap.hyper .l{font-size:.58rem;opacity:.6}
footer{margin-top:2.2rem;font-size:.85rem;opacity:.55}
@media(max-width:640px){.cap .c{font-size:.7rem}.cap.bound .l{font-size:.5rem}}
</style>
<h1>hyperkey cheatsheet</h1>
<p class="sub">hold ⇪ caps lock (raycast → ⌃⌥⇧⌘) + the lit key</p>
<div class="kb">$keyboard</div>
<footer>⌘tab is disabled on purpose — that's what the lit keys are for.</footer>
HTML

# opens in your default browser; set CHEATSHEET_BROWSER to a bundle id to pin one
if [ -n "${CHEATSHEET_BROWSER:-}" ]; then
  /usr/bin/open -b "$CHEATSHEET_BROWSER" "$out"
else
  /usr/bin/open "$out"
fi
