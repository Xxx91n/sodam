#!/bin/bash
# PROTOTYPE / THROWAWAY - issue #142 Linux(WSLg) backend + window probe. Do not ship.
set +e
echo "=== sodam processes ==="
pgrep -a sodam
echo "=== which backend (env of running sodam) ==="
for p in $(pgrep -x sodam); do
  echo "--- pid $p ---"
  tr '\0' '\n' < /proc/$p/environ | grep -E "^(DISPLAY|WAYLAND_DISPLAY|XDG_SESSION_TYPE|XDG_RUNTIME_DIR|WAYLAND|QT_QPA|GDK_BACKEND)=" || true
  echo "sockets:"
  ls -l /proc/$p/fd 2>/dev/null | grep -iE "socket|wayland|X11" | head -20
done
echo "=== X11 windows named SodaM ==="
export DISPLAY=:0
for w in $(xdotool search --name 'SodaM' 2>/dev/null); do
  echo "wid=$w pid=$(xdotool getwindowpid $w 2>/dev/null) name=$(xdotool getwindowname $w 2>/dev/null)"
  xdotool getwindowgeometry --shell "$w" 2>/dev/null | tr '\n' ' '; echo
done
echo "=== all visible windows (top 20) ==="
xdotool search --onlyvisible --name '.' 2>/dev/null | head -20 | while read -r w; do
  echo "$w pid=$(xdotool getwindowpid $w 2>/dev/null) name=$(xdotool getwindowname $w 2>/dev/null | head -c 60)"
done
echo "=== display geometry / mouse ==="
xdotool getdisplaygeometry
xdotool getmouselocation --shell
echo "=== image / event tools ==="
for t in import convert xdotool xev xinput xprop xwininfo; do
  p=$(command -v "$t" 2>/dev/null); echo "$t=${p:-MISSING}"
done
echo "=== v0.3.9 deb / packages anywhere ==="
find /opt /root /tmp /mnt/c/sodam /mnt/c/sodam-142 -maxdepth 4 \( -iname '*0.3.9*' -o -iname '*.deb' -o -iname '*pkg.tar.zst*' \) 2>/dev/null | head -30
echo "=== other probe scripts running? ==="
ps aux | grep -E "drive_linux|linux_click|probe.sh|scan.sh|xdotool" | grep -v grep | head -20
echo "=== #136 linux evidence on windows side ==="
ls -la /mnt/c/sodam/prototype/136-hover-residue/evidence 2>/dev/null | grep -iE "linux|lnx" | head -30
