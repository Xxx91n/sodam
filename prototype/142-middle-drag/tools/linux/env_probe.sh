#!/bin/bash
# PROTOTYPE / THROWAWAY - issue #142 Linux(WSLg) environment probe. Do not ship.
set +e
echo "=== /opt ==="
ls -la /opt 2>/dev/null
echo "=== sodam binaries ==="
find /opt /usr /root -maxdepth 5 -name sodam -type f 2>/dev/null | while read -r f; do
  echo "$f  sha=$(sha256sum "$f" | cut -c1-16)  size=$(stat -c%s "$f")  mtime=$(stat -c%y "$f")"
done
echo "=== installed pkgs (interesting ones) ==="
pacman -Q 2>/dev/null | grep -iE "sodam|wayland|xorg|xdotool|xev|libx11|glibc" | head -40
dpkg -l 2>/dev/null | grep -i sodam | head -10
echo "=== tools ==="
for t in xdotool xev xinput wmctrl xprop xwininfo xdpyinfo weston-info wtype ydotool grim scrot python3 pacman dpkg Xvfb; do
  p=$(command -v "$t" 2>/dev/null)
  echo "$t=${p:-MISSING}"
done
echo "=== env ==="
env | grep -E "DISPLAY|WAYLAND|XDG_|WSL|QT_|GDK_" | sort
echo "=== processes ==="
ps aux | grep -iE "sodam|weston|Xwayland|Xorg" | grep -v grep | head -25
echo "=== /root ==="
ls -la /root | head -40
echo "=== /tmp ==="
ls -la /tmp | head -40
echo "=== weston.log tail ==="
tail -25 /mnt/wslg/weston.log 2>/dev/null
echo "=== stderr.log ==="
cat /mnt/wslg/stderr.log 2>/dev/null | tail -20
echo "=== X11 socket ==="
ls -la /tmp/.X11-unix /mnt/wslg/.X11-unix 2>/dev/null
