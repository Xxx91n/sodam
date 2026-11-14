#!/bin/bash
# PROTOTYPE / THROWAWAY - issue #136 Linux residue driver. Do not ship.
set -u
export DISPLAY=:0
EV=/mnt/c/sodam/prototype/136-hover-residue/evidence
CSV=$EV/linux_residue.csv

WID=$(/root/probe.sh wid)
eval "$(xdotool getwindowgeometry --shell $WID)"
echo "window id=$WID pos=$X,$Y size=${WIDTH}x$HEIGHT"
xdotool getdisplaygeometry

BTN_MIN_X=869; BTN_MAX_X=913; BTN_CLOSE_X=957; BTN_Y=16

patch_mean() { # img bx by -> "R,G,B"
  convert "$1" -crop 13x13+$2+$3 +repage -resize 1x1 -depth 8 txt:- 2>/dev/null | tail -1 | \
    awk -F'[(,)]' '{print $2","$3","$4}' | tr -d ' #'
}

delta() { # mean1 mean2 (R,G,B) -> max channel diff
  echo "$1 $2" | awk -F'[ ,]' '{d=0; for(i=1;i<=3;i++){e=$i-$(i+3); e=e<0?-e:e; if(e>d)d=e} print d}'
}

neutral() {
  xdotool mousemove $((X + 400)) $((Y + 300))
  sleep 0.4
}

neutral
import -window $WID /tmp/_base.png
BASE_MIN=$(patch_mean /tmp/_base.png $BTN_MIN_X $BTN_Y)
BASE_MAX=$(patch_mean /tmp/_base.png $BTN_MAX_X $BTN_Y)
BASE_CLOSE=$(patch_mean /tmp/_base.png $BTN_CLOSE_X $BTN_Y)
echo "baseline min=$BASE_MIN max=$BASE_MAX close=$BASE_CLOSE"

[ -f "$CSV" ] || echo "button,dir,dist,delta,lit,btnRGB" >> "$CSV"

probe_case() { # button dir dist
  local btn=$1 dir=$2 dist=$3
  local bx by name
  case $btn in
    min) bx=$BTN_MIN_X;; max) bx=$BTN_MAX_X;; close) bx=$BTN_CLOSE_X;;
  esac
  by=$BTN_Y
  case $dir in
    right) ex=$((X + WIDTH + dist)); ey=$((Y + by));;
    up) ex=$((X + bx)); ey=$((Y - dist));;
    upright) ex=$((X + WIDTH + dist*70/100)); ey=$((Y + by - dist*70/100));;
  esac
  neutral
  xdotool mousemove $((X + bx)) $((Y + by))
  sleep 0.5
  xdotool mousemove $ex $ey
  sleep 0.9
  name="lnx_${btn}_${dir}_${dist}"
  import -window $WID /tmp/_res.png
  convert /tmp/_res.png -crop 260x44+$((WIDTH-260))+0 +repage $EV/$name.png
  local mean base dl lit
  case $btn in
    min) base=$BASE_MIN; bx=$BTN_MIN_X;; max) base=$BASE_MAX; bx=$BTN_MAX_X;; close) base=$BASE_CLOSE; bx=$BTN_CLOSE_X;;
  esac
  mean=$(patch_mean /tmp/_res.png $bx $by)
  dl=$(delta "$base" "$mean")
  if [ "$dl" -gt 15 ]; then lit=YES; else lit=no; fi
  echo "$btn,$dir,$dist,$dl,$lit,$mean" >> "$CSV"
  echo "$btn $dir d=$dist delta=$dl lit=$lit rgb=$mean"
}

for btn in min max close; do
  for dir in right up upright; do
    for d in 5 15 60 200; do
      probe_case $btn $dir $d
    done
  done
done

# re-enter recovery: hover close, fling right 60, then move back into content area
neutral
xdotool mousemove $((X + BTN_CLOSE_X)) $((Y + BTN_Y))
sleep 0.5
xdotool mousemove $((X + WIDTH + 60)) $((Y + BTN_Y))
sleep 0.9
xdotool mousemove $((X + 400)) $((Y + 300))
sleep 0.9
import -window $WID /tmp/_reenter.png
RE_MEAN=$(patch_mean /tmp/_reenter.png $BTN_CLOSE_X $BTN_Y)
echo "re-enter close mean=$RE_MEAN (baseline $BASE_CLOSE)"
echo "done"
