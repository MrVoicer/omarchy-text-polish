#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# keys.sh — Polish's global shortcuts (Hyprland / Omarchy).
#   keys.sh apply   write ~/.config/hypr/polish.lua from your choices, load it, check it
#   keys.sh list    show each action, its key, and whether it's active
#
# Your choices live in ~/.local/state/text-polish/keys.conf, one per line:
#   reply = SHIFT + ALT + Alt_R      a key (Hyprland syntax)
#   read2 =                          empty: no key for that action
#   rewrite = ALT + Alt_R !          "!" takes the key over from another binding
# Actions not listed use the defaults below. Polish only ever writes its own file,
# polish.lua (loaded by one require line in hyprland.lua), never bindings.lua.
#
# A key that another binding already uses is skipped and reported, unless you
# mark it with "!". After writing, Hyprland is reloaded; if it reports a config
# error, the previous files are put back.
set -uo pipefail
DIR=$(dirname "$(readlink -f "$0")")
# shellcheck source=lib.sh
. "$DIR/lib.sh"
HYPR=${POLISH_HYPR_DIR:-$HOME/.config/hypr}
OUT=$HYPR/polish.lua
MAIN=$HYPR/hyprland.lua
CONF=$(polish_state_dir)/keys.conf
REQUIRE='require("hypr.polish")   -- Polish shortcuts (written by text-polish/keys.sh)'

# action | description | default key | polish arguments
ACTIONS=(
  "rewrite|Rewrite selected text|ALT + Alt_R|"
  "rewrite2|Rewrite selected text|SUPER + ALT + R|"
  "reply|Reply to selected text|SHIFT + ALT + Alt_R|--mode reply"
  "reply2|Reply to selected text|SUPER + ALT + Y|--mode reply"
  "read|Read selected text|CTRL + ALT + Alt_R|--mode read"
  "read2|Read selected text|SUPER + ALT + E|--mode read"
  "clipboard|Reply to copied text|SUPER + ALT + C|--clipboard --mode reply"
  "undo|Undo last Replace, Insert or Paste|SUPER + ALT + Z|--undo"
)
# Descriptions Polish used before it had its own file (so they don't count as clashes).
LEGACY='^(Polish: |Rewrite selected text with AI|Reply to selected text with AI|Read selected text with AI|AI reply to copied text|AI rewrite of copied text|Undo last AI rewrite)'

# The key chosen for ACTION (keys.conf, else the default). Prints "KEYS|FORCE".
chosen() {
  local id=$1 def=$2 line k force=0
  if [[ -f $CONF ]]; then
    line=$(grep -E "^[[:space:]]*$id[[:space:]]*=" "$CONF" | tail -1)
    if [[ -n $line ]]; then
      k=${line#*=}; k=$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' <<<"$k")
      [[ $k == *'!' ]] && { force=1; k=$(sed 's/[[:space:]]*!$//' <<<"$k"); }
      printf '%s|%s\n' "$k" "$force"; return
    fi
  fi
  printf '%s|0\n' "$def"
}

# "SUPER + ALT + R" -> "72 r" (Hyprland's modmask and lower-cased key).
mask_of() {
  local m=0 t key=""
  IFS='+' read -ra parts <<<"$1"
  for t in "${parts[@]}"; do
    t=$(tr -d '[:space:]' <<<"$t"); [[ -n $t ]] || continue
    case ${t^^} in
      SHIFT) ((m |= 1)) ;; CTRL|CONTROL) ((m |= 4)) ;; ALT) ((m |= 8)) ;;
      SUPER|WIN|LOGO|MOD4) ((m |= 64)) ;; *) key=$t ;;
    esac
  done
  printf '%s %s\n' "$m" "${key,,}"
}

# Who else uses KEYS? Prints "description<TAB>its keys", or nothing.
taken_by() {
  local mk; mk=$(mask_of "$1")
  jq -r --argjson m "${mk%% *}" --arg k "${mk#* }" --arg legacy "$LEGACY" '
    # A Right Alt binding may ignore modifiers (Omarchy dictation does), so any
    # other Alt_R binding clashes with every Right Alt combo.
    [.[] | select((.key | ascii_downcase) == $k and (.modmask == $m or $k == "alt_r"))
         | select((.description // "") | test($legacy) | not)
         | [(.description // .arg // "another binding"),
            ([if (.modmask/64|floor)%2==1 then "SUPER" else empty end,
              if (.modmask/4|floor)%2==1 then "CTRL" else empty end,
              if (.modmask/8|floor)%2==1 then "ALT" else empty end,
              if .modmask%2==1 then "SHIFT" else empty end, .key] | join(" + "))] | @tsv][0] // empty' <<<"$BINDS"
}

lua_str() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; printf '"%s"' "$s"; }

cmd=${1:-list}
case $cmd in apply|list) ;; *) echo "usage: keys.sh apply|list" >&2; exit 2 ;; esac
command -v hyprctl >/dev/null || { echo "Hyprland isn't running (no hyprctl)." >&2; exit 1; }
BINDS=$(hyprctl binds -j 2>/dev/null) || BINDS='[]'

polish_cmd=$(printf '%q' "$DIR/polish")
body="" unbinds="" report=""
for a in "${ACTIONS[@]}"; do
  IFS='|' read -r id desc def args <<<"$a"
  IFS='|' read -r keys force < <(chosen "$id" "$def")
  if [[ -z $keys ]]; then report+=$(printf '  %-10s  (none)' "$id")$'\n'; continue; fi
  IFS=$'\t' read -r other other_keys < <(taken_by "$keys"; echo)
  if [[ -n $other && $force != 1 ]]; then
    report+=$(printf '  %-10s  %-22s  SKIPPED: already used by "%s" (add " !" after it in keys.conf to take it over)' "$id" "$keys" "$other")$'\n'
    continue
  fi
  opts=""
  # Right Alt binds must not swallow the key: inside the popup it's still Alt (Alt+M, Alt+1...).
  [[ ${keys,,} == *alt_r* ]] && opts=", { non_consuming = true }"
  # Taking a key over: remove the other binding (by its own keys) first.
  # Once taken over, the other binding no longer shows up, so keep the line we
  # wrote last time (tagged with the action) for as long as "!" stays.
  if [[ $force == 1 ]]; then
    if [[ -n $other_keys ]]; then unbinds+="pcall(hl.unbind, $(lua_str "$other_keys"))  -- takeover:$id"$'\n'
    elif [[ -f $OUT ]]; then
      prev=$(grep -E "^pcall\(hl\.unbind, \"[^\"]*\"\)  -- takeover:$id\$" "$OUT" | head -1)
      [[ -n $prev ]] && unbinds+=$prev$'\n'
    fi
  fi
  body+="o.bind($(lua_str "$keys"), $(lua_str "Polish: $desc"), $(lua_str "$polish_cmd${args:+ $args}")$opts)"$'\n'
  report+=$(printf '  %-10s  %s%s' "$id" "$keys" "${other:+  (taken over from \"$other\")}")$'\n'
done

if [[ $cmd == list ]]; then printf 'Polish shortcuts (%s):\n%s' "${CONF/#$HOME/\~}" "$report"; exit 0; fi

[[ -f $MAIN ]] || { echo "No $MAIN; is this Omarchy's Lua config?" >&2; exit 1; }
run=$(polish_run_dir) || exit 1
bak_out=$(mktemp "$run/polish.lua.XXXXXX"); bak_main=$(mktemp "$run/hyprland.lua.XXXXXX")
trap 'rm -f "$bak_out" "$bak_main"' EXIT
had_out=0; [[ -f $OUT ]] && { cp -- "$OUT" "$bak_out"; had_out=1; }
cp -- "$MAIN" "$bak_main"

{
  echo "-- Polish shortcuts. Written by $(basename "$DIR")/keys.sh; edits here are overwritten."
  echo "-- Change keys in ~/.local/state/text-polish/keys.conf, then run keys.sh apply."
  echo "if not (o and o.bind and hl) then return end"
  # Takeovers first: an unbind after Polish's own bind would remove Polish's key.
  printf '%s' "$unbinds" "$body"
} >"$OUT.tmp" && mv -f "$OUT.tmp" "$OUT"

# Load it from hyprland.lua (once), right after your own bindings.
if ! grep -qF 'require("hypr.polish")' "$MAIN"; then
  if grep -q '^require("hypr.bindings")' "$MAIN"; then
    awk -v line="$REQUIRE" '{ print } /^require\("hypr.bindings"\)/ && !done { print line; done = 1 }' "$MAIN" >"$MAIN.tmp"
  else
    { cat "$MAIN"; printf '\n%s\n' "$REQUIRE"; } >"$MAIN.tmp"
  fi
  cat "$MAIN.tmp" >"$MAIN" && rm -f "$MAIN.tmp"   # cat >: keeps a symlinked hyprland.lua a symlink
fi

hyprctl reload >/dev/null 2>&1
errs=$(hyprctl configerrors 2>/dev/null | sed '/^[[:space:]]*$/d')
if [[ -n $errs ]]; then
  if ((had_out)); then cp -- "$bak_out" "$OUT"; else rm -f "$OUT"; fi
  cat "$bak_main" >"$MAIN"
  hyprctl reload >/dev/null 2>&1
  printf 'Hyprland reported an error, so the previous shortcuts were put back:\n%s\n' "$errs" >&2
  exit 1
fi
printf 'Polish shortcuts are active:\n%s' "$report"
