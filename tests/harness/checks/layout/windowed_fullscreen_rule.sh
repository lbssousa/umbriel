#!/usr/bin/env bash
# harness: outputs=1
# default_windowed_fullscreen opens a window in windowed fullscreen: the configure before its first buffer already
# carries the fullscreen state, and the window keeps its tile. Real fullscreen from default_fullscreen wins over it.
set -euo pipefail

readonly CLIENT="${UMBRIEL_UNMAP_CLIENT:-./build-debug/tests/unmap-client}"
readonly RULE_LOG="$UMBRIEL_RUNTIME_DIR/windowed-fullscreen-rule.log"
readonly BOTH_LOG="$UMBRIEL_RUNTIME_DIR/windowed-fullscreen-rule-both.log"

cat >> "$UMBRIEL_CONFIG" <<'CONF'

[animation]
enabled = false

[[window_rule]]
match.title = "^windowed-rule"
default_windowed_fullscreen = true

[[window_rule]]
match.title = "^windowed-rule-both"
default_fullscreen = true
CONF
"$UMBRIEL" msg config-reload > /dev/null

field() {
  "$UMBRIEL" windows --json | jq -r --arg title "$1" --arg field "$2" '.[] | select(.title == $title) | .[$field]'
}

expect_field() {
  local title=$1 name=$2 want=$3 got=
  got=$(field "$title" "$name")
  if [[ $got != "$want" ]]; then
    echo "expected $title $name=$want, got $got: $("$UMBRIEL" windows --json)"
    exit 1
  fi
}

wait_for_window() {
  for _ in $(seq 60); do
    [[ -n $(field "$1" id) ]] && return 0
    sleep 0.05
  done
  echo "window $1 never mapped: $("$UMBRIEL" windows --json)"
  exit 1
}

LOG_CONFIGURES=1 "$CLIENT" windowed-rule > "$RULE_LOG" 2>&1 &
wait_for_window windowed-rule
"$UMBRIEL" settle
expect_field windowed-rule windowed_fullscreen true
expect_field windowed-rule fullscreen false
tile="$(field windowed-rule w)x$(field windowed-rule h)"
if [[ $tile == "1280x720" ]]; then
  echo "the ruled window must keep a tile smaller than the output: $tile"
  exit 1
fi
first=$(grep '^configured-state=' "$RULE_LOG" | head -1 || true)
if [[ $first != *" fullscreen" ]]; then
  echo "the first configure must already carry the fullscreen state, got '${first:-none}': $(cat "$RULE_LOG")"
  exit 1
fi

LOG_CONFIGURES=1 "$CLIENT" windowed-rule-both > "$BOTH_LOG" 2>&1 &
wait_for_window windowed-rule-both
"$UMBRIEL" settle
expect_field windowed-rule-both fullscreen true
expect_field windowed-rule-both windowed_fullscreen false

echo "default_windowed_fullscreen opens in windowed fullscreen and default_fullscreen wins"
