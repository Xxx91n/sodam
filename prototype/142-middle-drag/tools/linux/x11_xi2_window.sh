#!/bin/bash
# PROTOTYPE / THROWAWAY - issue #142. XI2 without --root: see which window the
# release is actually delivered to when the pointer is outside.
set -u
export DISPLAY=:0
EV=/mnt/c/sodam-142/prototype/142-middle-drag/evidence/linux
LOG="$EV/x11_xi2_target.log"
: > "$LOG"
WID=$(xdotool search --name 'SodaM' | head -1)
eval "$(xdotool getwindowgeometry --shell "$WID")"
CX=$((X + WIDTH * 3 / 4)); CY=$((Y + HEIGHT / 2))
OX=$((X + WIDTH + 80)); OY=$CY
echo "wid=$(printf '0x%x' "$WID") inside=($CX,$CY) outside=($OX,$OY)" | tee -a "$LOG"

xdotool mousemove "$CX" "$CY"; sleep 0.3
stdbuf -oL -eL xinput test-xi2 4 > "$LOG.tmp" 2>&1 &
P=$!
sleep 0.6
xdotool mousedown 2; sleep 0.3
for i in 1 2 3; do xdotool mousemove $((CX + (OX - CX) * i / 3)) "$OY"; sleep 0.15; done
xdotool mouseup 2; sleep 0.4
xdotool mousemove "$CX" "$CY"; sleep 0.4
sleep 0.3
kill "$P" 2>/dev/null; wait "$P" 2>/dev/null
cat "$LOG.tmp" >> "$LOG"; rm -f "$LOG.tmp"

echo "=== ButtonPress / ButtonRelease blocks ===" | tee -a "$LOG"
grep -A 12 -E "EVENT type (4|5) \(Button" "$LOG" | head -80 | tee -a "$LOG"
echo "=== all 'windows:' lines ===" | tee -a "$LOG"
grep "windows:" "$LOG" | sort | uniq -c | tee -a "$LOG"
