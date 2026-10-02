#!/bin/bash
# Замір спалахами на екрані UI РМ (HDMI-A-1, ASUS): тимчасово правило labwc для gst-launch-1.0 -> HDMI-A-1, потім відновлення з копії.
# Запобіжник: systemd-run відновить rc.xml через 5 хв, навіть якщо сесія обірветься.
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0
C=~/.config/labwc/rc.xml; B=~/rc.xml.flash-backup
DEV=${1:-/dev/video0}
cp -p "$C" "$B" || exit 1
systemd-run --user --on-active=300 --unit=rcxml-restore sh -c "cmp -s $B $C || { cp -p $B $C; kill -HUP $(pgrep -x -u $(id -u) labwc); }" >/dev/null 2>&1
python3 - "$C" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '<windowRule identifier="gst-launch-1.0" serverDecoration="no" skipTaskbar="yes" skipWindowSwitcher="yes">\n    <action name="MoveToOutput" output="HDMI-A-2" />'
if s.count(old) != 1:
    sys.exit("rule not found")
open(p, "w").write(s.replace(old, old.replace("HDMI-A-2", "HDMI-A-1")))
PY
ok=$?
if [ $ok -eq 0 ]; then
    kill -HUP $(pgrep -x -u $(id -u) labwc); sleep 1
    grep -A1 'identifier="gst-launch-1.0"' "$C" | tail -1
    cd ~/latency
    RMFLASH_FMT=gray8 timeout 90 python3 rmflash.py asus_gray8_rpt "$DEV" 40 0.8 640x480@30 jpegdec 2>&1 | tail -1
    RMFLASH_FMT=i420 timeout 90 python3 rmflash.py asus_i420_720x576 "$DEV" 40 0.8 640x480@30 jpegdec 2>&1 | tail -1
fi
cp -p "$B" "$C"; kill -HUP $(pgrep -x -u $(id -u) labwc)
cmp "$B" "$C" && echo "rc.xml відновлено"
systemctl --user stop rcxml-restore.timer >/dev/null 2>&1
grep -A1 'identifier="gst-launch-1.0"' "$C" | tail -1
systemctl --user is-active kambala-display
