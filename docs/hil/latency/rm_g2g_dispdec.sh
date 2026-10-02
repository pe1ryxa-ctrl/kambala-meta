#!/bin/bash
# «Від скла до скла» з програмним декодером Flight Display (avdec_h264): чи заважають одне одному кодер і декодер на VideoCore.
# Тимчасово KWS_DISPLAY_DECODER у ~/kws/.env (копія), перезапуск kambala-display; наприкінці — відновлення.
TAG=${1:-g2gd}; N=${N:-100}; DEC=${DEC:-avdec_h264}
cd ~/latency
E=~/kws/.env; B=~/kws/.env.g2g-backup; cp -p "$E" "$B"
grep -v '^KWS_DISPLAY_DECODER=' "$B" > "$E.tmp" && echo "KWS_DISPLAY_DECODER=$DEC" >> "$E.tmp" && cat "$E.tmp" > "$E" && rm -f "$E.tmp"
systemctl --user restart kambala-display; sleep 5
VARIANTS=${VARIANTS:-"swdisp_hwjpeg_hwenc v4l2jpegdec v4l2
swdisp_swjpeg_x264 jpegdec x264"}
echo "$VARIANTS" | while read -r name jdec enc; do
  [ -z "$name" ] && continue
  pkill -f "camserve.p[y]"; sleep 1
  setsid nohup python3 camserve.py /dev/video0 640x480@30 2000 75 "$jdec" "$enc" > /tmp/camserve.log 2>&1 < /dev/null &
  sleep 15
  N=$N bash rm_g2g.sh "${TAG}_${name}" | grep -v -E "^(active|DONE|rc.xml)"
done
cat "$B" > "$E"; cmp -s "$B" "$E" && echo ".env відновлено"
systemctl --user restart kambala-display; sleep 3; systemctl --user is-active kambala-display
pkill -f "camserve.p[y]"; sleep 1
setsid nohup python3 camserve.py > /tmp/camserve.log 2>&1 < /dev/null &
sleep 2; echo DONE
