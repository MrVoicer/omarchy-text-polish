#!/usr/bin/env bash
# apply.sh replace|insert|paste WINDOW_ADDRESS TEXT [ORIGINAL] [LABEL]
#   replace: paste over the selection.  insert: paste right after it.
#   paste:   paste at the cursor (Reply mode), without touching any selection.
# Puts TEXT on the clipboard, refocuses the window the selection came from and
# pastes. Then offers Undo for 10 minutes: a notification button, or
# `apply.sh undo` (polish --undo, SUPER+ALT+Z), which refocuses the window and
# sends the app's own undo (Ctrl+Z). Terminals have no undo (Ctrl+Z would
# suspend the program), so there Undo copies the original back to the clipboard.
here=$(dirname "$(readlink -f "$0")")
run="${XDG_RUNTIME_DIR:-/tmp}/text-polish"; mkdir -p -m 700 "$run"
state="$run/last-apply.json"
UNDO_SECS=600

is_terminal() {
  case "${1,,}" in
    *ghostty*|*kitty*|*alacritty*|*foot*|*terminal*|*wezterm*|org.omarchy.agent) return 0 ;;
  esac
  return 1
}
focus() {   # focus WINDOW_ADDRESS; fails if that window is gone
  [[ -n $1 && $1 != null ]] || return 1
  hyprctl clients -j 2>/dev/null | jq -e --arg a "$1" 'any(.[]; .address==$a)' >/dev/null || return 1
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$1\" })" >/dev/null 2>&1 ||
    hyprctl dispatch focuswindow "address:$1" >/dev/null 2>&1
  sleep 0.08
}
note() { notify-send -a Polish -t 4000 "Polish" "$1"; }

if [[ ${1:-} == undo ]]; then
  if [[ ! -s $state ]]; then note "Nothing to undo."; exit 0; fi
  IFS=$'\t' read -r t addr class how < <(jq -r '[.t, .addr, .class, .how] | @tsv' "$state")
  original=$(jq -r '.original' "$state")
  rm -f "$state"   # one undo per apply
  if (( $(date +%s) - t > UNDO_SECS )); then note "Nothing to undo (it's been over 10 minutes)."; exit 0; fi
  if is_terminal "$class" || ! focus "$addr"; then
    if [[ $how == replace && -n $original ]]; then
      printf '%s' "$original" | wl-copy
      note "Can't undo there. Your original text is on the clipboard."
    else
      note "Can't undo there; remove the pasted text by hand."
    fi
    exit 0
  fi
  wtype -M ctrl -k z -m ctrl
  exit 0
fi

mode=$1 addr=$2 text=$3 original=${4:-} label=${5:-}
if [[ $mode == insert ]]; then
  printf ' %s' "$text" | wl-copy   # space + text as one paste, so one undo removes all of it
else
  printf '%s' "$text" | wl-copy
fi
sleep 0.25   # let the popup's layer surface go away and focus settle
focus "$addr"
class=$(hyprctl clients -j 2>/dev/null | jq -r --arg a "$addr" '.[]|select(.address==$a).class' | head -1)
[[ $mode == insert ]] && wtype -k Right    # collapse the selection to its end
if is_terminal "$class"; then
  wtype -M ctrl -M shift -k v -m shift -m ctrl
else
  wtype -M ctrl -k v -m ctrl
fi

# Remember it for Undo, and offer the button.
jq -n --arg addr "$addr" --arg class "$class" --arg how "$mode" --arg original "$original" \
  '{t: (now|floor), addr: $addr, class: $class, how: $how, original: $original}' >"$state.tmp" && mv "$state.tmp" "$state"
case $mode in replace) verb=Replaced ;; insert) verb=Inserted ;; *) verb=Pasted ;; esac
msg="$verb${label:+ ($label)}. Undo: click Undo, or Super+Alt+Z."
setsid -f bash -c '
  act=$(notify-send -a Polish -t 10000 -A undo=Undo "Polish" "$1")
  [[ $act == undo ]] && exec "$2/apply.sh" undo
' _ "$msg" "$here" >/dev/null 2>&1 </dev/null
