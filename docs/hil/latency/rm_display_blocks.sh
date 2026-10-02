#!/bin/bash
# Чергування блоками на Daewoo (пілот): labwc / labwc+allowTearing / kmssink; BLOCKS x PER_BLOCK на варіант.
# Сирі значення -> ~/latency/<TAG>_{labwc,tear,kms}.raw, підсумок -> latpool.py. Лише РМ-1.
TAG=${1:-blk}; BLOCKS=${BLOCKS:-4}; PB=${PB:-50}; DEV=${DEV:-/dev/video0}; ROI=${ROI_DW:-0.70,0.74,0.96,0.95}
cd ~/latency; rm -f ${TAG}_*.raw
C=~/.config/labwc/rc.xml; B=~/rc.xml.blocks-backup; cp -p "$C" "$B"
systemd-run --user --on-active=1800 --unit=rcxml-restore-b sh -c "cmp -s $B $C || { cp -p $B $C; kill -HUP \$(pgrep -x labwc); }" >/dev/null 2>&1
TEARRC=~/rc.xml.tear; python3 - "$B" "$TEARRC" <<'PY'
import sys
s = open(sys.argv[1]).read(); tag = "<allowTearing>fullscreenForced</allowTearing>"
s = s.replace("<core>", "<core>\n    " + tag, 1) if "<core>" in s else s.replace("</labwc_config>", "  <core>\n    " + tag + "\n  </core>\n</labwc_config>", 1)
open(sys.argv[2], "w").write(s)
PY
sess() { export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0; }
fl() { RMFLASH_FMT=i420 RMFLASH_ROI=$ROI RMFLASH_RAW=~/latency/${TAG}_$1.raw timeout 120 python3 rmflash.py "${TAG}_$1_b$2" "$DEV" "$PB" 0.8 640x480@30 jpegdec 2>&1 | tail -1; }
for b in $(seq 1 "$BLOCKS"); do
  sess; cp -p "$B" "$C"; kill -HUP "$(pgrep -x -u "$(id -u)" labwc)"; sleep 1; fl labwc "$b"
  cp -p "$TEARRC" "$C"; kill -HUP "$(pgrep -x -u "$(id -u)" labwc)"; sleep 1; fl tear "$b"
  cp -p "$B" "$C"; kill -HUP "$(pgrep -x -u "$(id -u)" labwc)"
  pkill -x -u "$(id -u)" labwc; sleep 3; unset WAYLAND_DISPLAY
  RMFLASH_FMT=i420 RMFLASH_ROI=$ROI RMFLASH_RAW=~/latency/${TAG}_kms.raw RMFLASH_SINK="kmssink connector-id=44 can-scale=true render-rectangle=<0,0,800,480>" \
    sudo -n -E timeout 120 python3 rmflash.py "${TAG}_kms_b$b" "$DEV" "$PB" 0.8 640x480@30 jpegdec 2>&1 | tail -1
  sudo -n chown "$(id -u)" ~/latency/${TAG}_kms.raw
  sudo -n systemctl restart getty@tty1; sleep 25
done
cmp -s "$B" "$C" && echo "rc.xml = копія"; systemctl --user stop rcxml-restore-b.timer >/dev/null 2>&1
python3 latpool.py ${TAG}_labwc.raw ${TAG}_tear.raw ${TAG}_kms.raw
pgrep -a -x labwc || echo "labwc НЕ запущено"; sess; systemctl --user is-active kambala-display kambala-outputs
echo DONE
