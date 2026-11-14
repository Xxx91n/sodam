#!/bin/bash
# PROTOTYPE / THROWAWAY - issue #142. Only adds read-only X11 event tools, no build.
set +e
export PACMAN_ARGS="--noconfirm --needed"
echo "=== pacman: xorg-xev xorg-xinput xorg-xprop xorg-xwininfo ==="
pacman -S $PACMAN_ARGS xorg-xev xorg-xinput xorg-xprop xorg-xwininfo 2>&1 | tail -40
echo "=== exit=$? ==="
echo "=== check ==="
for t in xev xinput xprop xwininfo; do printf '%s=%s\n' "$t" "$(command -v $t || echo MISSING)"; done
