#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Sets Polish up: registers the native-messaging host for Brave / Chromium (so
# the browser's "Rewrite with AI" menu can open the popup) and turns on the
# keyboard shortcuts (keys.sh). Safe to re-run.
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
# Shortcuts: Polish writes its own ~/.config/hypr/polish.lua (never your
# bindings.lua) and loads it with one line in hyprland.lua. Keys another binding
# already uses are skipped and listed; change them in
# ~/.local/state/text-polish/keys.conf and run keys.sh apply again.
echo
if command -v hyprctl >/dev/null && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  "$DIR/keys.sh" apply || echo "Shortcuts weren't set up (see above). Fix keys.conf, then run $DIR/keys.sh apply"
else
  echo "Hyprland isn't running here, so shortcuts weren't set up. Later, run: $DIR/keys.sh apply"
fi
cat <<MSG

Next: the browser menu (optional). Open brave://extensions (or chrome://extensions),
enable Developer mode, "Load unpacked" -> $DIR/browser-extension
MSG
