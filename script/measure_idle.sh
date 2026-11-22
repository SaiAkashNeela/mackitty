#!/usr/bin/env bash
# Measures MacKitty's idle CPU, memory and wakeups in three states:
# window in front, app hidden, and window closed (menu bar only).
# usage: script/measure_idle.sh [path/to/MacKitty.app] [seconds-per-state]
set -euo pipefail

APP="${1:-/Applications/MacKitty.app}"
SECS="${2:-20}"
NAME="MacKitty"
SAMPLES=$(( SECS / 2 ))

pkill -x "$NAME" >/dev/null 2>&1 || true
sleep 1
open -n "$APP"
for _ in $(seq 1 20); do pgrep -x "$NAME" >/dev/null && break; sleep 0.5; done
PID=$(pgrep -x "$NAME" | head -n 1)
[ -n "$PID" ] || { echo "MacKitty did not start" >&2; exit 1; }
WS=$(pgrep -x WindowServer | head -n 1)
sleep 5 # let launch work settle

# Averages %CPU and idle wakeups over the window; reports the last memory footprint.
measure() {
  top -l "$SAMPLES" -s 2 -stats pid,cpu,mem,idlew -pid "$PID" -pid "$WS" 2>/dev/null |
    awk -v app="$PID" -v ws="$WS" -v label="$1" '
      $1 == app { n++; if (n > 1) { cpu += $2; w += $4; c++ } mem = $3 }
      $1 == ws  { m++; if (m > 1) { wcpu += $2; wc++ } }
      END { printf "%-16s app CPU %5.1f%%  WindowServer %5.1f%%  footprint %-7s idle wakeups/s %5.1f\n",
                   label, cpu / (c ? c : 1), wcpu / (wc ? wc : 1), mem, w / (c ? c : 1) / 2 }'
}

osascript -e "tell application \"$NAME\" to activate" >/dev/null 2>&1 || true
sleep 2
measure "window in front"

osascript -e "tell application \"System Events\" to set visible of process \"$NAME\" to false" >/dev/null
sleep 2
measure "app hidden"

osascript -e "tell application \"System Events\" to set visible of process \"$NAME\" to true" >/dev/null
sleep 1
osascript -e "tell application \"System Events\" to tell process \"$NAME\" to click (first button of window 1 whose subrole is \"AXCloseButton\")" >/dev/null 2>&1 || true
sleep 2
measure "window closed"

pkill -x "$NAME" >/dev/null 2>&1 || true
