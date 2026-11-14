#!/bin/bash
# PROTOTYPE / THROWAWAY - issue #136 Linux probe helpers. Do not ship.
# Usage: linux_probe.sh <cmd> [args]
set -u
export DISPLAY=:0

case "$1" in
  wid)
    xdotool search --name 'SodaM' | head -1
    ;;
  shot)
    # shot <wid> <outfile>
    import -window "$2" "$3"
    ;;
  info)
    xdotool getwindowname "$2"
    xdotool getwindowgeometry "$2"
    ;;
  geo)
    eval "$(xdotool getwindowgeometry --shell "$2")"
    echo "$X,$Y,$WIDTH,$HEIGHT"
    ;;
  strip)
    # strip <wid> <outfile> : capture window, crop top-right 260x44
    import -window "$2" /tmp/_full.png
    eval "$(xdotool getwindowgeometry --shell "$2")"
    convert /tmp/_full.png -crop 260x44+$((WIDTH-260))+0 +repage "$3"
    ;;
  mouse)
    xdotool mousemove "$2" "$3"
    ;;
  click)
    xdotool click 1
    ;;
  *)
    echo "unknown cmd"
    exit 1
    ;;
esac
