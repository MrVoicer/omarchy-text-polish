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

# polish_agent_error ID LABEL RC RAW: what went wrong with an agent run, in one
# plain sentence plus the next step (the raw error is appended by the caller).
polish_agent_error() {
  local id=$1 label=$2 rc=$3 raw=${4,,} login next="Retry with Ctrl+R, or switch agent with Alt+A."
  case $id in
    claude) login="run \"claude\" in a terminal and use /login" ;;
    codex) login="run \"codex login\" in a terminal" ;;
    opencode) login="run \"opencode auth login\" in a terminal" ;;
    *) login="open $label in a terminal and sign in" ;;
  esac
  if (( rc == 124 )); then
    echo "$label took too long, so Polish stopped it. $next"
  elif (( rc == 127 )) || [[ $raw == *"command not found"* ]]; then
    echo "$label isn't installed. Switch agent with Alt+A."
  elif [[ $raw =~ (rate.?limit|usage.?limit|quota|too\ many\ requests|\ 429|limit\ reached|hit\ your\ limit|overloaded|\ 529|capacity) ]]; then
    echo "$label is at its usage limit or overloaded right now. Try again later, or switch agent with Alt+A."
  elif [[ $raw =~ (not\ logged\ in|please\ log\ ?in|/login|unauthori[sz]ed|\ 401|authenticat|api\ key|credential|token\ (has\ )?expired|invalid.*token|sign\ in) ]]; then
    echo "$label isn't signed in. To fix it, $login. Or switch agent with Alt+A."
  elif [[ $raw =~ (enotfound|econnrefused|econnreset|etimedout|getaddrinfo|could\ not\ resolve|network\ error|offline|connection\ (refused|reset|error)|failed\ to\ connect|error\ sending\ request) ]]; then
    echo "Couldn't reach $label. Check your internet connection, then retry with Ctrl+R."
  elif [[ $raw =~ model.*(not\ found|not\ available|not\ supported|does\ not\ exist|no\ access|not\ have\ access) ]]; then
    echo "$label can't use the model it was asked for (check your plan or model setting). Switch agent with Alt+A."
  elif (( rc == 0 )); then
    echo "$label returned an empty answer. $next"
  else
    echo "$label failed (exit $rc). $next"
  fi
}
