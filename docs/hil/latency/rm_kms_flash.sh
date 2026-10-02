#!/bin/bash
# Ціна композитора: той самий кадр I420 720x576 через labwc (waylandsink) і через kmssink без labwc,
# на ASUS (HDMI-A-1) і на Daewoo (HDMI-A-2, екран пілота). Камера бачить обидва екрани: окремі ROI.
# Лише для РМ-1 (RPi 4), який більше не бережемо як РМ. Сесія відновлюється перезапуском getty@tty1.
DEV=${DEV:-/dev/video0}; N=${N:-40}
ROI_ASUS=${ROI_ASUS:-0.15,0.25,0.60,0.60}; ROI_DW=${ROI_DW:-0.70,0.74,0.96,0.95}
cd ~/latency
run() { RMFLASH_FMT=i420 timeout 90 python3 rmflash.py "$@" "$DEV" "$N" 0.8 640x480@30 jpegdec 2>&1 | tail -1; }
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0
# A2. labwc, Daewoo (штатне правило gst-launch-1.0 -> HDMI-A-2)
RMFLASH_ROI=$ROI_DW run A_labwc_daewoo
# A1. labwc, ASUS: тимчасово правило -> HDMI-A-1
C=~/.config/labwc/rc.xml; B=~/rc.xml.flash-backup; cp -p "$C" "$B"
python3 - "$C" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '<windowRule identifier="gst-launch-1.0" serverDecoration="no" skipTaskbar="yes" skipWindowSwitcher="yes">\n    <action name="MoveToOutput" output="HDMI-A-2" />'
if s.count(old) != 1: sys.exit("rule not found")
open(p, "w").write(s.replace(old, old.replace("HDMI-A-2", "HDMI-A-1")))
PY
kill -HUP $(pgrep -x -u $(id -u) labwc); sleep 1
RMFLASH_ROI=$ROI_ASUS run A_labwc_asus
cp -p "$B" "$C"; kill -HUP $(pgrep -x -u $(id -u) labwc); cmp -s "$B" "$C" && echo "rc.xml відновлено"
# B. без композитора
pkill -x -u $(id -u) labwc; sleep 3
pgrep -a -x labwc && echo "УВАГА: labwc перезапустився"
unset WAYLAND_DISPLAY
krun() { RMFLASH_FMT=i420 RMFLASH_ROI=$1 RMFLASH_SINK="kmssink connector-id=$2 can-scale=true render-rectangle=<0,0,$3>" \
  sudo -n -E timeout 90 python3 rmflash.py "$4" "$DEV" "$N" 0.8 640x480@30 jpegdec 2>&1 | tail -1; }
krun "$ROI_ASUS" 35 1920,1080 B_kms_asus
krun "$ROI_DW" 44 800,480 B_kms_daewoo
sudo -n systemctl restart getty@tty1; sleep 25
pgrep -a -x labwc || echo "labwc НЕ запущено"
systemctl --user is-active kambala-display
