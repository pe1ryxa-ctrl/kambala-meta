#!/bin/bash
# Матриця затримки показу на РМ-1: labwc (кадр 720x576 і рідний розмір) і kmssink без композитора (= еквівалент DRM lease),
# ASUS (HDMI-A-1) і Daewoo (HDMI-A-2, пілот). TAG — мітка серії; TEAR=1 — тимчасово <allowTearing>fullscreenForced</allowTearing>;
# NOKMS=1 — без варіантів kmssink. Лише РМ-1 (RPi 4), який не бережемо як РМ. rc.xml — з копією і запобіжником.
TAG=${1:-run}; DEV=${DEV:-/dev/video0}; N=${N:-40}
ROI_ASUS=${ROI_ASUS:-0.15,0.25,0.60,0.60}; ROI_DW=${ROI_DW:-0.70,0.74,0.96,0.95}
cd ~/latency
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0
labwc_pid() { pgrep -x -u "$(id -u)" labwc; }
run() { # name roi size keep_hz [extra env]
  env RMFLASH_FMT=i420 RMFLASH_ROI="$2" RMFLASH_SIZE="$3" RMFLASH_KEEP_HZ="$4" ${5:+$5} \
    timeout 120 python3 rmflash.py "${TAG}_$1" "$DEV" "$N" 0.8 640x480@30 jpegdec 2>&1 | tail -1; }
C=~/.config/labwc/rc.xml; B=~/rc.xml.matrix-backup; cp -p "$C" "$B"
systemd-run --user --on-active=900 --unit=rcxml-restore-m sh -c "cmp -s $B $C || { cp -p $B $C; kill -HUP \$(pgrep -x labwc); }" >/dev/null 2>&1
edit() { python3 - "$C" "$1" <<'PY'
import sys
p, mode = sys.argv[1], sys.argv[2]; s = open(p).read()
if mode == "asus":
    old = '<windowRule identifier="gst-launch-1.0" serverDecoration="no" skipTaskbar="yes" skipWindowSwitcher="yes">\n    <action name="MoveToOutput" output="HDMI-A-2" />'
    if s.count(old) != 1: sys.exit("rule not found")
    s = s.replace(old, old.replace("HDMI-A-2", "HDMI-A-1"))
elif mode == "tear":
    tag = "<allowTearing>fullscreenForced</allowTearing>"
    if tag not in s:
        if "<core>" in s: s = s.replace("<core>", "<core>\n    " + tag, 1)
        else: s = s.replace("</labwc_config>", "  <core>\n    " + tag + "\n  </core>\n</labwc_config>", 1)
open(p, "w").write(s)
PY
}
[ "$TEAR" = 1 ] && { edit tear || exit 1; }
kill -HUP "$(labwc_pid)"; sleep 1
echo "labwc $(labwc --version | awk '{print $2}') TEAR=${TEAR:-0}"
run labwc_daewoo_720    "$ROI_DW"   720x576   30
run labwc_daewoo_native "$ROI_DW"   800x480   30
edit asus || exit 1; kill -HUP "$(labwc_pid)"; sleep 1
run labwc_asus_720      "$ROI_ASUS" 720x576   30
run labwc_asus_native   "$ROI_ASUS" 1920x1080 5
cp -p "$B" "$C"; kill -HUP "$(labwc_pid)"; cmp -s "$B" "$C" && echo "rc.xml відновлено"
systemctl --user stop rcxml-restore-m.timer >/dev/null 2>&1
if [ "$NOKMS" != 1 ]; then
  pkill -x -u "$(id -u)" labwc; sleep 3; unset WAYLAND_DISPLAY
  krun() { env RMFLASH_FMT=i420 RMFLASH_ROI="$1" RMFLASH_SIZE="$2" RMFLASH_KEEP_HZ="$3" \
      RMFLASH_SINK="kmssink connector-id=$4 can-scale=true render-rectangle=<0,0,$5>" \
      sudo -n -E timeout 120 python3 rmflash.py "${TAG}_$6" "$DEV" "$N" 0.8 640x480@30 jpegdec 2>&1 | tail -1; }
  krun "$ROI_DW"   720x576 30 44 800,480   kms_daewoo_720
  krun "$ROI_DW"   800x480 30 44 800,480   kms_daewoo_native
  krun "$ROI_ASUS" 720x576 30 35 1920,1080 kms_asus_720
  sudo -n systemctl restart getty@tty1; sleep 25
fi
pgrep -a -x labwc || echo "labwc НЕ запущено"
systemctl --user is-active kambala-display kambala-outputs
