#!/usr/bin/env bash
# apply.sh --stdin     read a JSON request on stdin, hand it to a detached copy of
#                      itself and exit 0 at once (the popup waits for that, then
#                      closes). Request: {how: replace|insert|paste, addr, text,
#                      original, label, editable}
# apply.sh undo        undo the last apply (SUPER+ALT+Z, the toast's Undo button)
#
# Text never travels on a command line (argv is visible to other users and is
# limited to ~128 KB per argument). The paste goes only to the window the text
# came from: Polish checks that window still exists, puts the text on the
# clipboard, and sends the keys to *that window* with Hyprland's send_shortcut
# (never globally, so a focus change can't redirect it; and with exact
# modifiers, so keys still held from a hotkey don't leak in). If the window is
# gone, nothing is pasted and a toast says the text is on the clipboard.
#   replace: paste over the selection.  insert: paste right after it.
#   paste:   Reply mode; pastes at the cursor. If the selection is in an
#            editable field, it's collapsed first so the message isn't replaced.
# Undo sends Ctrl+Z to that window; terminals have no undo (Ctrl+Z would
# suspend the program), so there Undo copies the original back to the clipboard.
here=$(dirname "$(readlink -f "$0")")
# shellcheck source=lib.sh
. "$here/lib.sh"
run=$(polish_run_dir) || exit 1
state="$run/last-apply.json"
UNDO_SECS=600
umask 077

if [[ ${1:-} == --stdin ]]; then
  req=$(mktemp "$run/apply-XXXXXX.json") || exit 1
  cat >"$req" && jq -e '.how and (.text | type == "string")' "$req" >/dev/null || { rm -f "$req"; exit 1; }
  setsid -f "$0" --request "$req" </dev/null >/dev/null 2>&1
  exit 0
fi

is_terminal() {
  case "${1,,}" in
    *ghostty*|*kitty*|*alacritty*|*foot*|*terminal*|*wezterm*|org.omarchy.agent) return 0 ;;
  esac
  return 1
}
window_exists() { [[ -n $1 && $1 != null ]] && hyprctl clients -j 2>/dev/null | jq -e --arg a "$1" 'any(.[]; .address==$a)' >/dev/null; }
window_class() { hyprctl clients -j 2>/dev/null | jq -r --arg a "$1" '.[] | select(.address==$a) | .class' | head -1; }
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$run/undo.log"; }
# Write the undo state atomically (unique temp file, then rename).
save_state() { local t; t=$(mktemp "$state.XXXXXX") && cat >"$t" && mv -f "$t" "$state"; }
# Keycode of a letter in the *active* keyboard layout (send_shortcut takes keycodes).
keycode_of() {
  local kb layouts variants idx code
  kb=$(hyprctl devices -j 2>/dev/null | jq -c '[.keyboards[] | select(.main)][0] // .keyboards[0] // {}' 2>/dev/null)
  [[ -n $kb ]] || kb='{}'   # (devices JSON can be briefly invalid while a virtual keyboard exists)
  layouts=$(jq -r '.layout // "us"' <<<"$kb"); variants=$(jq -r '.variant // ""' <<<"$kb")
  idx=$(( $(jq -r '.active_layout_index // 0' <<<"$kb") + 1 ))   # xkbcli numbers layouts from 1
  # One row per layout that has the letter; take the active layout's row.
  code=$(xkbcli how-to-type --layout "${layouts:-us}" --variant "$variants" "$1" 2>/dev/null |
    awk -v want="$idx" '$1 ~ /^[0-9]+$/ { if (first == "") first = $1; if ($3 == want) { print $1; found = 1; exit } }
                        END { if (!found && first != "") print first }')
  printf '%s\n' "${code:-$2}"
}
# send MODS KEYCODE ADDR: deliver one shortcut to that window only.
send() {
  local out
  out=$(hyprctl dispatch "hl.dsp.send_shortcut({ mods = \"$1\", key = \"code:$2\", window = \"address:$3\" })" 2>&1)
  [[ $out == ok ]] || { log "send_shortcut $1+$2 -> $out"; return 1; }
}
RIGHT=114   # Right arrow: same keycode on every layout

# Apply/undo and their state are one transaction: two quick presses can't both
# act. Anything that outlives us (wl-copy stays running to serve the clipboard,
# the toast) must not inherit fd 8, or it would hold the lock: hence the 8>&-.
exec 8>"$run/undo.lock"
flock -w 5 8 || { log "lock busy"; exit 1; }

if [[ ${1:-} == undo ]]; then
  pkill -f "quickshell -p $here/toast.qml" 2>/dev/null
  if [[ ! -s $state ]]; then log "undo: no state"; polish_toast "Nothing to undo."; exit 0; fi
  IFS=$'\t' read -r t addr class how undone < <(jq -r '[.t, .addr, .class, .how, (.undone // false)] | @tsv' "$state")
  original=$(jq -r '.original' "$state")
  log "undo: how=$how class=$class age=$(( $(date +%s) - t ))s undone=$undone"
  # One undo per apply: a second press must not undo something else in the app.
  if [[ $undone == true ]]; then polish_toast "Already undone."; exit 0; fi
  if (( $(date +%s) - t > UNDO_SECS )); then polish_toast "Nothing to undo (it's been over 10 minutes)."; exit 0; fi
  mark_undone() { jq '.undone = true' "$state" | save_state; }
  if is_terminal "$class"; then
    if [[ $how == replace && -n $original ]]; then
      printf '%s' "$original" | wl-copy 8>&-
      mark_undone
      polish_toast "Terminals have no undo. Your original text is on the clipboard."
    else
      polish_toast "Terminals have no undo; remove the pasted text by hand." warn
    fi
    exit 0
  fi
  if ! window_exists "$addr"; then
    if [[ $how == replace && -n $original ]]; then
      printf '%s' "$original" | wl-copy 8>&-
      polish_toast "That window is gone. Your original text is on the clipboard."
    else
      polish_toast "That window is gone, so there's nothing to undo." warn
    fi
    exit 0
  fi
  # Ctrl+Z to that window with exactly CTRL (your Super/Alt from the hotkey
  # are ignored). Only a delivered undo uses up the Undo.
  if send CTRL "$(keycode_of z 52)" "$addr"; then
    mark_undone
  else
    polish_toast "Couldn't send undo to that window. Try Ctrl+Z there." warn
  fi
  exit 0
fi

if [[ ${1:-} != --request || ! -s ${2:-} ]]; then echo "usage: apply.sh --stdin | undo" >&2; exit 2; fi
req=$2
how=$(jq -r '.how' "$req"); addr=$(jq -r '.addr // ""' "$req")
text=$(jq -r '.text' "$req"); original=$(jq -r '.original // ""' "$req")
label=$(jq -r '.label // ""' "$req"); editable=$(jq -r '.editable // "unknown"' "$req")
rm -f "$req"

if [[ $how == insert ]]; then
  clip=" $text"   # space + text as one paste, so one undo removes all of it
else
  clip=$text
fi
if ! printf '%s' "$clip" | wl-copy 8>&-; then
  log "$how: clipboard failed"; polish_toast "Couldn't use the clipboard, so nothing was pasted." warn; exit 1
fi
sleep 0.25   # let the popup's layer surface go away
if ! window_exists "$addr"; then
  log "$how: window $addr gone; not pasting"
  polish_toast "The original window is gone, so nothing was pasted. The text is on your clipboard." warn
  exit 0
fi
# Bring it forward (it should see the paste as normal input), then send keys to it.
hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" >/dev/null 2>&1
sleep 0.08
class=$(window_class "$addr")
vcode=$(keycode_of v 55)
# Collapse the selection to its end for insert, and for a reply whose selected
# message sits in an editable field (else the paste would replace it).
if [[ $how == insert || ( $how == paste && $editable == yes ) ]]; then send "" $RIGHT "$addr"; fi
if is_terminal "$class"; then pmods="CTRL SHIFT"; else pmods="CTRL"; fi
if ! send "$pmods" "$vcode" "$addr"; then
  polish_toast "Pasting failed; the text is on your clipboard." warn; exit 1
fi

# Remember it for Undo, and offer the button.
jq -n --arg addr "$addr" --arg class "$class" --arg how "$how" --arg original "$original" \
  '{t: (now|floor), addr: $addr, class: $class, how: $how, original: $original}' | save_state
log "$how: class=$class"
flock -u 8
case $how in replace) verb=Replaced ;; insert) verb=Inserted ;; *) verb=Pasted ;; esac
polish_toast "$verb${label:+ · $label}" undo
