#!/bin/bash
# PROTOTYPE / THROWAWAY - issue #142. Can a native Wayland client even start in
# WSLg? Short-lived instance, killed right after the check, so it does not sit
# on top of the other session's window.
set +e
EV=/mnt/c/sodam-142/prototype/142-middle-drag/evidence/linux
mkdir -p "$EV"
LOG="$EV/wayland_try.log"
: > "$LOG"
RAW=/tmp/sodam142_wayland_raw.log
: > "$RAW"
HOME_DIR=/tmp/sodam142-wl-home
rm -rf "$HOME_DIR"; mkdir -p "$HOME_DIR/.config"
log() { echo "$*" | tee -a "$LOG"; }

log "=== runtime dir / socket ==="
ls -la /mnt/wslg/runtime-dir/wayland-0 2>&1 | tee -a "$LOG"
log "=== start: DISPLAY unset, WAYLAND_DISPLAY kept, WAYLAND_DEBUG=1 ==="
env -u DISPLAY \
    WAYLAND_DISPLAY=wayland-0 \
    XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir \
    HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" \
    WAYLAND_DEBUG=1 \
    /opt/s038/usr/bin/sodam > "$RAW" 2>&1 &
NEWPID=$!
log "new_pid=$NEWPID"
sleep 7
if kill -0 "$NEWPID" 2>/dev/null; then log "alive_after_7s=yes"; else log "alive_after_7s=no"; fi
log "=== sodam processes now ==="
pgrep -a sodam | tee -a "$LOG"
log "=== fds of the new pid (wayland socket?) ==="
ls -l /proc/$NEWPID/fd 2>/dev/null | grep -iE "wayland|socket" | head -12 | tee -a "$LOG"
log "=== env of the new pid ==="
tr '\0' '\n' < /proc/$NEWPID/environ 2>/dev/null | grep -E "^(DISPLAY|WAYLAND_DISPLAY|XDG_RUNTIME_DIR|WAYLAND_DEBUG)=" | tee -a "$LOG"
log "=== WAYLAND_DEBUG: pointer / seat / surface lines ==="
grep -iE "wl_pointer|wl_seat|wl_surface|wl_compositor|button|enter|leave" "$RAW" | head -30 | tee -a "$LOG"
log "=== WAYLAND_DEBUG: first 25 lines ==="
head -25 "$RAW" | tee -a "$LOG"
log "=== WSLg weston.log tail ==="
tail -18 /mnt/wslg/weston.log 2>/dev/null | tee -a "$LOG"

log "=== cleanup: kill ONLY the pid we started ==="
kill "$NEWPID" 2>/dev/null
sleep 1
kill -9 "$NEWPID" 2>/dev/null
wait "$NEWPID" 2>/dev/null
pgrep -a sodam | tee -a "$LOG"
log "=== done ==="
