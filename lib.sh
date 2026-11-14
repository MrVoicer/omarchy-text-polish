# Shared helpers for polish, apply.sh and rewrite.sh (sourced, not run).

# Private per-user runtime dir: $XDG_RUNTIME_DIR/text-polish, or ~/.cache/text-polish
# when that's missing. Never a shared /tmp path another user could pre-create.
# Refuses a dir we don't own or that is a symlink.
polish_run_dir() {
  local base=${XDG_RUNTIME_DIR:-}
  [[ -n $base && -d $base && -O $base ]] || base="$HOME/.cache"
  local d="$base/text-polish"
  mkdir -p "$d" 2>/dev/null
  if [[ -L $d || ! -O $d ]]; then echo "polish: unsafe runtime dir $d" >&2; return 1; fi
  chmod 700 "$d"
  printf '%s\n' "$d"
}

# Persistent state (settings, history, agent): private to you (dir 700, files 600).
polish_state_dir() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/text-polish"
  mkdir -p "$d" && chmod 700 "$d"
  find "$d" -maxdepth 1 -type f ! -perm 600 -exec chmod 600 {} + 2>/dev/null
  printf '%s\n' "$d"
}

# polish_toast MESSAGE [undo|info|warn] — Polish's own toast (shows even with
# Do Not Disturb on, takes no keyboard focus). "undo" adds the Undo button.
polish_toast() {
  local here run
  here=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
  run=$(polish_run_dir) || return
  pkill -f "quickshell -p $here/toast.qml" 2>/dev/null
  POLISH_TOAST_MSG=$1 POLISH_TOAST_KIND=${2:-info} POLISH_DIR=$here \
  POLISH_MONITOR=$(hyprctl monitors -j 2>/dev/null | jq -r '.[]|select(.focused).name') \
    setsid -f quickshell -p "$here/toast.qml" >"$run/toast.log" 2>&1 </dev/null 8>&- 9>&-   # never inherit a lock
}
