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
  cat >"$d/NativeMessagingHosts/com.voicer.text_polish.json" <<JSON
{
  "name": "com.voicer.text_polish",
  "description": "Polish AI rewrite popup",
  "path": "$DIR/native-host.py",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$ID/"]
}
JSON
  echo "registered native host in $d"
done
cat <<MSG

Next:
  1. Browser: open brave://extensions (or chrome://extensions), enable Developer
     mode, "Load unpacked" -> $DIR/browser-extension
  2. Hotkey (Omarchy / Hyprland Lua), add to ~/.config/hypr/bindings.lua:
     o.bind("SUPER + ALT + R", "Rewrite selected text with AI", '"$DIR/polish"')
     then: hyprctl reload && hyprctl configerrors
MSG
