#!/bin/bash
# PROBE: locate Linux titlebar button glyphs (row y=16, x 850..980). Throwaway.
set -u
export DISPLAY=:0
WID=$(/root/probe.sh wid)
import -window "$WID" /tmp/_full.png
convert /tmp/_full.png -crop 130x1+850+16 +repage -depth 8 txt:- 2>/dev/null | tail -n +2 | \
  awk -F'[(,)]' '{x=$1; sub(":.*","",x); r=$2;g=$3;b=$4; print x, (r+g+b<450) ? "#" : "."}' | \
  awk '{s=$1; c=$2; if (c=="#") {if (start=="") start=s} else {if (start!=""){print "run", start, "-", prev; start=""}} prev=s} END {if (start!="") print "run", start, "-", prev}'
echo "runs are relative to x=850; add 850 for absolute window-local x"
