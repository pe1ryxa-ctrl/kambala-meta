#!/bin/bash
# usage: g2g_crop.sh LABEL [full]
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0
L=$1
POS=$(wlr-randr | awk '/^HDMI-A-2/{f=1} f&&/Position/{print $2; exit}'); X=${POS%,*}
rm -f /tmp/c_${L}_*
if [ "${2:-}" = full ]; then grim -o HDMI-A-2 -s 0.4 /tmp/c_${L}_full.png; echo full; exit; fi
for i in 1 2 3 4 5 6; do
  t=$(date -u +%S.%3N)
  grim -s 0.35 -g "$((X+40)),30 700x450" /tmp/c_${L}_${i}_${t}.png
  sleep 0.9
done
ls /tmp/c_${L}_*
