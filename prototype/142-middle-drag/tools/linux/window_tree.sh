#!/bin/bash
# PROTOTYPE / THROWAWAY - issue #142. Figure out which X11 window really gets the input.
set +e
export DISPLAY=:0
EV=/mnt/c/sodam-142/prototype/142-middle-drag/evidence/linux
mkdir -p "$EV"
OUT="$EV/x11_window_tree.log"
: > "$OUT"
echo "=== root tree (top 60) ===" >> "$OUT"
xwininfo -root -tree 2>&1 | head -60 >> "$OUT"
echo "=== windows owned by sodam pid 2811 ===" >> "$OUT"
xdotool search --pid 2811 2>/dev/null | while read -r w; do
  echo "wid=$w dec=$(printf '0x%x' "$w") name=$(xdotool getwindowname "$w" 2>/dev/null)" >> "$OUT"
done
echo "=== props of 0x600001 ===" >> "$OUT"
xprop -id 0x600001 WM_CLASS WM_NAME _NET_WM_PID _NET_WM_WINDOW_TYPE 2>&1 | head -12 >> "$OUT"
echo "=== props of 0x200420 ===" >> "$OUT"
xprop -id 0x200420 WM_CLASS WM_NAME _NET_WM_PID _NET_WM_WINDOW_TYPE 2>&1 | head -12 >> "$OUT"
echo "=== geometry of both ===" >> "$OUT"
for w in 0x600001 0x200420; do echo "-- $w --" >> "$OUT"; xwininfo -id "$w" 2>&1 | grep -E "Absolute|Relative|Width|Height|Map State" >> "$OUT"; done
echo "=== window at the probe point ===" >> "$OUT"
xdotool mousemove 1213 540 >/dev/null 2>&1
xdotool getmouselocation --shell >> "$OUT"
cat "$OUT"
