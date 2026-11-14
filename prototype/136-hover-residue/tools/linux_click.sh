#!/bin/bash
# PROBE: Linux stale click checks. Throwaway.
set -u
export DISPLAY=:0
EV=/mnt/c/sodam/prototype/136-hover-residue/evidence
WID=$(/root/probe.sh wid)
eval "$(xdotool getwindowgeometry --shell $WID)"
BTN_CLOSE_X=957; BTN_Y=16

neutral() {
  xdotool mousemove $((X + 400)) $((Y + 300))
  sleep 0.4
}
alive() { pgrep -x sodam > /dev/null && echo alive || echo dead; }

# control: click below button row inside window
neutral
xdotool mousemove $((X + BTN_CLOSE_X)) $((Y + 40))
sleep 0.3
xdotool click 1
sleep 0.8
echo "ctrl_below_button: $(alive)"

# stale: hover close, fling right 5 (outside window), click there
neutral
xdotool mousemove $((X + BTN_CLOSE_X)) $((Y + BTN_Y))
sleep 0.5
xdotool mousemove $((X + WIDTH + 5)) $((Y + BTN_Y))
sleep 0.4
xdotool click 1
sleep 0.8
echo "stale_click_right5: $(alive)"

# stale: hover close, fling right 60, click (over whatever is next to window)
neutral
xdotool mousemove $((X + BTN_CLOSE_X)) $((Y + BTN_Y))
sleep 0.5
xdotool mousemove $((X + WIDTH + 60)) $((Y + BTN_Y))
sleep 0.4
xdotool click 1
sleep 0.8
echo "stale_click_right60: $(alive)"

# stale: hover close, fling up 200, click (above window)
neutral
xdotool mousemove $((X + BTN_CLOSE_X)) $((Y + BTN_Y))
sleep 0.5
xdotool mousemove $((X + BTN_CLOSE_X)) $((Y - 200))
sleep 0.4
xdotool click 1
sleep 0.8
echo "stale_click_up200: $(alive)"

neutral
echo "done"
