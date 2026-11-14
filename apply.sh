#!/usr/bin/env bash
# apply.sh replace|insert|paste WINDOW_ADDRESS TEXT [ORIGINAL] [LABEL]
#   replace: paste over the selection.  insert: paste right after it.
#   paste:   paste at the cursor (Reply mode), without touching any selection.
# Puts TEXT on the clipboard, refocuses the window the selection came from and
# pastes. If that window is gone (or won't take focus), it pastes nowhere: the
# text stays on the clipboard and a toast says so. After a paste it offers Undo
# for 10 minutes: the toast's button (toast.qml), or `apply.sh undo`
# (polish --undo, SUPER+ALT+Z), which sends the app's own undo (Ctrl+Z) to that
# window. Terminals have no undo (Ctrl+Z would suspend the program), so there
# Undo copies the original back to the clipboard.
here=$(dirname "$(readlink -f "$0")")
# shellcheck source=lib.sh
. "$here/lib.sh"
run=$(polish_run_dir) || exit 1
state="$run/last-apply.json"
UNDO_SECS=600
umask 077

is_terminal() {
  case "${1,,}" in
    *ghostty*|*kitty*|*alacritty*|*foot*|*terminal*|*wezterm*|org.omarchy.agent) return 0 ;;
  esac
  return 1
}
# focus WINDOW_ADDRESS: succeeds only if that window exists and is now active.
focus() {
  [[ -n $1 && $1 != null ]] || return 1
  hyprctl clients -j 2>/dev/null | jq -e --arg a "$1" 'any(.[]; .address==$a)' >/dev/null || return 1
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$1\" })" >/dev/null 2>&1 ||
    hyprctl dispatch focuswindow "address:$1" >/dev/null 2>&1
  local _
  for _ in 1 2 3 4 5; do
    sleep 0.05
    [[ $(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty') == "$1" ]] && return 0
  done
  return 1
}
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$run/undo.log"; }
# Write the undo state atomically (unique temp file, then rename).
save_state() { local t; t=$(mktemp "$state.XXXXXX") && cat >"$t" && mv -f "$t" "$state"; }
# Keycode of Z in the *active* keyboard layout (send_shortcut takes keycodes).
z_keycode() {
  local kb layouts variants active code
  kb=$(hyprctl devices -j 2>/dev/null | jq -c '[.keyboards[] | select(.main)][0] // .keyboards[0] // {}')
  layouts=$(jq -r '.layout // "us"' <<<"$kb"); variants=$(jq -r '.variant // ""' <<<"$kb")
  active=$(jq -r '.active_keymap // ""' <<<"$kb")
  # One row per layout that has Z; prefer the row whose layout name is the active keymap.
  code=$(xkbcli how-to-type --layout "${layouts:-us}" --variant "$variants" z 2>/dev/null |
    awk -v act="$active" '$1 ~ /^[0-9]+$/ { if (first == "") first = $1; if (act != "" && index($0, act)) { print $1; found = 1; exit } }
                          END { if (!found && first != "") print first }')
  printf '%s\n' "${code:-52}"
}

# Undo (and its state) is one transaction: two quick presses can't both undo.
# Anything that outlives us (wl-copy stays running to serve the clipboard, the
# toast) must not inherit fd 8, or it would hold the lock: hence the 8>&-.
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
  jq '.undone = true' "$state" | save_state
  if (( $(date +%s) - t > UNDO_SECS )); then polish_toast "Nothing to undo (it's been over 10 minutes)."; exit 0; fi
  if is_terminal "$class" || ! focus "$addr"; then
    if [[ $how == replace && -n $original ]]; then
      printf '%s' "$original" | wl-copy 8>&-
      polish_toast "Can't undo there. Your original text is on the clipboard."
    else
      polish_toast "Can't undo there; remove the pasted text by hand." warn
    fi
    exit 0
  fi
  # Send Ctrl+Z through Hyprland to that window. With the SUPER+ALT+Z hotkey your
  # Super and Alt are still held, and a typed Ctrl+Z would arrive as
  # Super+Alt+Ctrl+Z (not undo); send_shortcut uses exactly the mods we give.
  zcode=$(z_keycode)
  out=$(hyprctl dispatch "hl.dsp.send_shortcut({ mods = \"CTRL\", key = \"code:$zcode\", window = \"address:$addr\" })" 2>&1)
  log "undo sent: zcode=$zcode -> $out"
  if [[ $out != ok ]]; then
    sleep 0.6   # fallback: give the hotkey's modifiers time to be released
    wtype -M ctrl -k z -m ctrl
  fi
  exit 0
fi

mode=$1 addr=$2 text=$3 original=${4:-} label=${5:-}
if [[ $mode == insert ]]; then
  clip=" $text"   # space + text as one paste, so one undo removes all of it
else
  clip=$text
fi
if ! printf '%s' "$clip" | wl-copy 8>&-; then
  log "$mode: clipboard failed"; polish_toast "Couldn't use the clipboard, so nothing was pasted." warn; exit 1
fi
sleep 0.25   # let the popup's layer surface go away and focus settle
# Paste only into the window the text came from, and only if it's really focused.
if ! focus "$addr"; then
  log "$mode: window $addr gone or not focusable; not pasting"
  polish_toast "The original window is gone, so nothing was pasted. The text is on your clipboard." warn
  exit 0
fi
class=$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty')
[[ $mode == insert ]] && wtype -k Right    # collapse the selection to its end
if is_terminal "$class"; then
  wtype -M ctrl -M shift -k v -m shift -m ctrl
else
  wtype -M ctrl -k v -m ctrl
fi || { log "$mode: wtype failed"; polish_toast "Pasting failed; the text is on your clipboard." warn; exit 1; }

# Remember it for Undo, and offer the button.
jq -n --arg addr "$addr" --arg class "$class" --arg how "$mode" --arg original "$original" \
  '{t: (now|floor), addr: $addr, class: $class, how: $how, original: $original}' | save_state
log "$mode: class=$class"
flock -u 8
case $mode in replace) verb=Replaced ;; insert) verb=Inserted ;; *) verb=Pasted ;; esac
polish_toast "$verb${label:+ · $label}" undo
