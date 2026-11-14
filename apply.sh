#!/usr/bin/env bash
# apply.sh replace|insert|paste WINDOW_ADDRESS TEXT
# paste: paste at the cursor (Reply mode), without touching any selection.
# Puts TEXT on the clipboard, refocuses the window the selection came from and
# pastes over the selection (replace) or right after it (insert).
mode=$1 addr=$2 text=$3
printf '%s' "$text" | wl-copy
sleep 0.25   # let the popup's layer surface go away and focus settle
if [[ -n $addr && $addr != null ]]; then
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" >/dev/null 2>&1 ||
    hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1
  sleep 0.08
fi
class=$(hyprctl clients -j 2>/dev/null | jq -r --arg a "$addr" '.[]|select(.address==$a).class' | head -1)
if [[ $mode == insert ]]; then
  wtype -k Right    # collapse the selection to its end
  wtype ' '
fi
case "${class,,}" in
  *ghostty*|*kitty*|*alacritty*|*foot*|*terminal*|*wezterm*|org.omarchy.agent)
    wtype -M ctrl -M shift -k v -m shift -m ctrl ;;
  *) wtype -M ctrl -k v -m ctrl ;;
esac
