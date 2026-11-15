#!/usr/bin/env bash
# Registers the native-messaging host for Brave / Chromium so the
# "Rewrite with AI" context menu can open the popup. Safe to re-run.
set -euo pipefail
DIR=$(dirname "$(readlink -f "$0")")
ID=$(<"$DIR/extension-id.txt")
for d in ~/.config/BraveSoftware/Brave-Origin ~/.config/BraveSoftware/Brave-Browser \
         ~/.config/chromium ~/.config/google-chrome; do
  [[ -d $d ]] || continue
  mkdir -p "$d/NativeMessagingHosts"
  # jq builds the JSON, so any folder name (quotes, backslashes) stays valid.
  jq -n --arg path "$DIR/native-host.py" --arg origin "chrome-extension://$ID/" \
    '{name: "com.voicer.text_polish", description: "Polish AI rewrite popup",
      path: $path, type: "stdio", allowed_origins: [$origin]}' \
    >"$d/NativeMessagingHosts/com.voicer.text_polish.json"
  echo "registered native host in $d"
done
cat <<MSG

Next:
  1. Browser: open brave://extensions (or chrome://extensions), enable Developer
     mode, "Load unpacked" -> $DIR/browser-extension
  2. Hotkey (Omarchy / Hyprland Lua), add to ~/.config/hypr/bindings.lua:
     o.bind("SUPER + ALT + R", "Rewrite selected text with AI", '"$DIR/polish"')
     o.bind("SUPER + ALT + Y", "Reply to selected text with AI", '"$DIR/polish" --mode reply')
     o.bind("SUPER + ALT + E", "Read selected text with AI", '"$DIR/polish" --mode read')
     o.bind("SUPER + ALT + C", "AI reply to copied text", '"$DIR/polish" --clipboard --mode reply')
     o.bind("SUPER + ALT + Z", "Undo last AI rewrite", '"$DIR/polish" --undo')
     then: hyprctl reload && hyprctl configerrors
MSG
