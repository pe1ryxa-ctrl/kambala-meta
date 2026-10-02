#!/bin/bash
# Розклад «від скла до скла» на РМ-1: спалах ASUS -> камера -> [V399 напряму | camserve локально | camserve через VPS] -> аналіз.
# Один годинник (РМ-1). Тимчасове правило labwc gst-launch-1.0 -> HDMI-A-1. ROI ASUS. N на варіант.
TAG=${1:-seg}; N=${N:-60}; ROI=${ROI_ASUS:-0.15,0.25,0.60,0.60}
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0
cd ~/latency
C=~/.config/labwc/rc.xml; B=~/rc.xml.seg-backup; cp -p "$C" "$B"
systemd-run --user --on-active=1800 --unit=rcxml-restore-s sh -c "cmp -s $B $C || { cp -p $B $C; kill -HUP \$(pgrep -x labwc); }" >/dev/null 2>&1
python3 - "$C" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '<windowRule identifier="gst-launch-1.0" serverDecoration="no" skipTaskbar="yes" skipWindowSwitcher="yes">\n    <action name="MoveToOutput" output="HDMI-A-2" />'
if s.count(old) != 1: sys.exit("rule not found")
open(p, "w").write(s.replace(old, old.replace("HDMI-A-2", "HDMI-A-1")))
PY
kill -HUP "$(pgrep -x -u "$(id -u)" labwc)"; sleep 1
R="rtph264depay ! h264parse ! avdec_h264"
RMFLASH_FMT=i420 RMFLASH_ROI=$ROI RMFLASH_CAPHEAD="rtspsrc location=rtsp://127.0.0.1:8554/video0 protocols=tcp latency=0 ! $R" \
  timeout 150 python3 rmflash.py "${TAG}_camserve_local" x "$N" 1.0 2>&1 | tail -1
RMFLASH_FMT=i420 RMFLASH_ROI=$ROI RMFLASH_CAPHEAD="rtspsrc location=rtsp://10.66.0.1:8554/node/sim protocols=tcp latency=0 ! $R" \
  timeout 150 python3 rmflash.py "${TAG}_via_vps_tcp" x "$N" 1.0 2>&1 | tail -1
RMFLASH_FMT=i420 RMFLASH_ROI=$ROI RMFLASH_CAPHEAD="rtspsrc location=rtsp://10.66.0.1:8554/node/sim protocols=udp latency=0 drop-on-latency=true ! $R" \
  timeout 150 python3 rmflash.py "${TAG}_via_vps_udp" x "$N" 1.0 2>&1 | tail -1
cp -p "$B" "$C"; kill -HUP "$(pgrep -x -u "$(id -u)" labwc)"; cmp -s "$B" "$C" && echo "rc.xml відновлено"
systemctl --user stop rcxml-restore-s.timer >/dev/null 2>&1; echo DONE
