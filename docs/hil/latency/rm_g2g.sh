#!/bin/bash
# Від скла до скла на РМ-1: тимчасове правило labwc gst-launch-1.0 -> HDMI-A-1 (ASUS) для спалахів, g2g.py, відновлення rc.xml.
# Flight Display (identifier kambala-flight) лишається на HDMI-A-2. Передумови: V399 на sim, sim — v4l2, на РМ обрано вузол sim, ARM вимкнено.
TAG=${1:-g2g}; N=${N:-200}; PER=${PER:-1.0}
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0
cd ~/latency
C=~/.config/labwc/rc.xml; B=~/rc.xml.g2g-backup; cp -p "$C" "$B"
systemd-run --user --on-active=1800 --unit=rcxml-restore-g sh -c "cmp -s $B $C || { cp -p $B $C; kill -HUP \$(pgrep -x labwc); }" >/dev/null 2>&1
python3 - "$C" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '<windowRule identifier="gst-launch-1.0" serverDecoration="no" skipTaskbar="yes" skipWindowSwitcher="yes">\n    <action name="MoveToOutput" output="HDMI-A-2" />'
if s.count(old) != 1: sys.exit("rule not found")
open(p, "w").write(s.replace(old, old.replace("HDMI-A-2", "HDMI-A-1")))
PY
ok=$?
if [ $ok -eq 0 ]; then
  kill -HUP "$(pgrep -x -u "$(id -u)" labwc)"; sleep 1
  G2G_RAW=~/latency/${TAG}.raw timeout $(( N * 2 + 60 )) python3 g2g.py "$TAG" "$N" "$PER" 2>&1 | tail -1
fi
cp -p "$B" "$C"; kill -HUP "$(pgrep -x -u "$(id -u)" labwc)"; cmp -s "$B" "$C" && echo "rc.xml відновлено"
systemctl --user stop rcxml-restore-g.timer >/dev/null 2>&1
systemctl --user is-active kambala-display
echo DONE
