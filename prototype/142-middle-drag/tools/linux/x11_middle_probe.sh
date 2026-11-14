#!/bin/bash
# PROTOTYPE / THROWAWAY - issue #142 Linux X11(WSLg/XWayland) middle-button probe.
# Question: after a middle press, does the window still get the release when the
# pointer is outside? xev -id listens on the real SodaM window; xdotool injects input.
set -u
export DISPLAY=:0
EV=/mnt/c/sodam-142/prototype/142-middle-drag/evidence/linux
mkdir -p "$EV"
STEPS="$EV/x11_steps.log"
XEV="$EV/x11_xev.log"
: > "$STEPS"
: > "$XEV"

WID=$(xdotool search --name 'SodaM' | head -1)
eval "$(xdotool getwindowgeometry --shell "$WID")"
PID=$(xdotool getwindowpid "$WID" 2>/dev/null)
echo "wid=$WID pid=$PID geo=$X,$Y ${WIDTH}x${HEIGHT}" | tee -a "$STEPS"
echo "screen=$(xdotool getdisplaygeometry | tr '\n' 'x')" | tee -a "$STEPS"
echo "X server=$(xdpyinfo 2>/dev/null | grep -E '^name of display|^version number' | tr '\n' ' ')" | tee -a "$STEPS"
echo "backend_env=$(tr '\0' '\n' < /proc/$PID/environ | grep -E '^(DISPLAY|WAYLAND_DISPLAY)=' | tr '\n' ' ')" | tee -a "$STEPS"
echo "pointer devices:" | tee -a "$STEPS"
xinput list --short 2>/dev/null | head -12 | tee -a "$STEPS"

CX=$((X + WIDTH * 3 / 4)); CY=$((Y + HEIGHT / 2))
OX=$((X + WIDTH + 80)); OY=$CY
echo "inside=($CX,$CY) outside=($OX,$OY)" | tee -a "$STEPS"

step() { echo "$(date +%H:%M:%S.%3N) $*" | tee -a "$STEPS"; }

XI2="$EV/x11_xi2.log"
: > "$XI2"
# stdbuf 强制行缓冲，不然 kill 的时候事件还压在缓冲区里没落盘
stdbuf -oL -eL xev -id "$WID" -event button -event mouse > "$XEV" 2>&1 &
XPID=$!
stdbuf -oL -eL xinput test-xi2 --root > "$XI2" 2>&1 &
IPID=$!
sleep 0.8
if ! kill -0 "$XPID" 2>/dev/null; then
  echo "xev failed to start:" | tee -a "$STEPS"; cat "$XEV" | tee -a "$STEPS"; exit 1
fi

step "00 move into window"
xdotool mousemove "$CX" "$CY"; sleep 0.4
step "01 MIDDLE DOWN inside"
xdotool mousedown 2; sleep 0.35
for i in 1 2 3 4 5 6; do
  nx=$((CX + (OX - CX) * i / 6))
  inside=yes; [ "$nx" -gt "$((X + WIDTH))" ] && inside=no
  step "02 drag step $i -> ($nx,$OY) inside_window=$inside"
  xdotool mousemove "$nx" "$OY"; sleep 0.18
done
step "03 MIDDLE UP outside window"
xdotool mouseup 2; sleep 0.45
step "04 move without buttons (3 steps, still outside)"
for dy in 20 60 120; do xdotool mousemove "$OX" $((OY + dy)); sleep 0.18; done
sleep 0.35
step "05 control: MIDDLE DOWN + UP inside window"
xdotool mousemove "$CX" "$CY"; sleep 0.3
xdotool mousedown 2; sleep 0.28
xdotool mouseup 2; sleep 0.35
step "06 control: MIDDLE press, minimize window, MIDDLE UP"
xdotool mousemove "$CX" "$CY"; sleep 0.3
xdotool mousedown 2; sleep 0.3
xdotool windowminimize "$WID"; sleep 0.6
xdotool mouseup 2; sleep 0.4
xdotool windowmap "$WID" 2>/dev/null; sleep 0.5

sleep 0.5
kill "$XPID" "$IPID" 2>/dev/null; wait "$XPID" 2>/dev/null; wait "$IPID" 2>/dev/null
step "done"
echo "=== XI2 全局原始输入（Button 相关）===" | tee -a "$STEPS"
grep -iE "EVENT type 1[45] |RawButton|ButtonPress|ButtonRelease|detail: 2" "$XI2" | head -40 | tee -a "$STEPS"
echo "=== XI2 行数 ===" | tee -a "$STEPS"; wc -l < "$XI2" | tee -a "$STEPS"

echo "=== 事件摘要（只看按键和进出窗口）===" | tee -a "$STEPS"
grep -E "ButtonPress|ButtonRelease|EnterNotify|LeaveNotify" "$XEV" \
  | sed -E 's/, synthetic [A-Z]+//; s/serial [0-9]+, //' | head -60 | tee -a "$STEPS"
echo "=== MotionNotify 条数 ===" | tee -a "$STEPS"
grep -c "MotionNotify" "$XEV" | tee -a "$STEPS"
echo "=== 窗口外那几步的坐标（root:）===" | tee -a "$STEPS"
grep -E "ButtonPress|ButtonRelease" "$XEV" | grep -oE 'root:\([0-9]+,[0-9]+\)' | head -20 | tee -a "$STEPS"
