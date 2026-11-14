#!/bin/bash
# PROTOTYPE / THROWAWAY - issue #142. Make sure the shared WSLg window was left usable.
set +e
export DISPLAY=:0
echo "=== sodam processes ==="
pgrep -a sodam
echo "=== window state ==="
for w in $(xdotool search --name 'SodaM' 2>/dev/null); do
  echo "wid=$w name=$(xdotool getwindowname "$w" 2>/dev/null)"
  xwininfo -id "$w" 2>/dev/null | grep -E "Absolute upper-left|Width:|Height:|Map State"
  xdotool getwindowgeometry --shell "$w" 2>/dev/null | tr '\n' ' '; echo
done
echo "=== pointer ==="
xdotool getmouselocation --shell
echo "=== tools installed for the probe ==="
pacman -Q xorg-xev xorg-xinput xorg-xprop xorg-xwininfo xdotool 2>/dev/null
echo "=== glibc ==="
ldd --version | head -1
