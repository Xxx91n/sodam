#!/bin/bash
# PROTOTYPE / THROWAWAY - issue #142. Second attempt at a native Wayland client:
# the first one died instantly. Add its own dbus session (that is how the X11
# instance was started) and record exactly why it exits.
set +e
EV=/mnt/c/sodam-142/prototype/142-middle-drag/evidence/linux
LOG="$EV/wayland_try2.log"; : > "$LOG"
RAW=/tmp/sodam142_wayland_raw2.log; : > "$RAW"
HOME_DIR=/tmp/sodam142-wl-home2
rm -rf "$HOME_DIR"; mkdir -p "$HOME_DIR/.config"
log() { echo "$*" | tee -a "$LOG"; }

BEFORE=$(pgrep -x sodam | sort -n)
log "=== sodam pids before: $BEFORE ==="

env -u DISPLAY \
    WAYLAND_DISPLAY=wayland-0 \
    XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir \
    XDG_SESSION_TYPE=wayland \
    HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" \
    WAYLAND_DEBUG=1 \
    dbus-run-session -- /opt/s038/usr/bin/sodam > "$RAW" 2>&1 &
WRAP=$!
log "wrapper_pid=$WRAP"
sleep 7
AFTER=$(pgrep -x sodam | sort -n)
log "=== sodam pids after 7s: $AFTER ==="
log "wrapper alive: $(kill -0 $WRAP 2>/dev/null && echo yes || echo no)"
NEW=$(comm -13 <(echo "$BEFORE") <(echo "$AFTER") | tr '\n' ' ')
log "new sodam pids: ${NEW:-none}"
for p in $NEW; do
  log "--- pid $p env ---"
  tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -E "^(DISPLAY|WAYLAND_DISPLAY|XDG_SESSION_TYPE|WAYLAND_DEBUG)=" | tee -a "$LOG"
  log "--- pid $p sockets ---"
  ls -l /proc/$p/fd 2>/dev/null | grep -i socket | head -8 | tee -a "$LOG"
done
log "=== raw stderr/stdout size=$(stat -c%s "$RAW") ==="
head -30 "$RAW" | tee -a "$LOG"
log "=== WAYLAND_DEBUG pointer lines ==="
grep -iE "wl_pointer|wl_seat|wl_surface|wl_compositor" "$RAW" | head -20 | tee -a "$LOG"
log "=== files the new instance wrote under its HOME ==="
find "$HOME_DIR" -type f 2>/dev/null | head -20 | tee -a "$LOG"
log "=== exit code of wrapper ==="
if kill -0 "$WRAP" 2>/dev/null; then log "still running (no exit code)"; else wait "$WRAP"; log "exit=$?"; fi

log "=== cleanup: kill ONLY the new pids + our wrapper ==="
for p in $NEW; do kill "$p" 2>/dev/null; done
kill "$WRAP" 2>/dev/null
sleep 1
for p in $NEW; do kill -9 "$p" 2>/dev/null; done
kill -9 "$WRAP" 2>/dev/null
wait "$WRAP" 2>/dev/null
log "=== sodam pids left: $(pgrep -x sodam | sort -n | tr '\n' ' ') ==="
log "=== done ==="
