#!/bin/bash
# Матриця «від скла до скла»: перезапуск camserve з (декодер JPEG, кодер) і серія g2g на кожен варіант.
# Аргументи: TAG; змінні N (дефолт 100). Варіанти — рядки "назва декодер кодер".
TAG=${1:-g2gm}; N=${N:-100}
cd ~/latency
VARIANTS=${VARIANTS:-"hwjpeg_hwenc v4l2jpegdec v4l2
swjpeg_hwenc jpegdec v4l2
swjpeg_x264 jpegdec x264
hwjpeg_x264 v4l2jpegdec x264"}
echo "$VARIANTS" | while read -r name dec enc; do
  [ -z "$name" ] && continue
  pkill -f "camserve.p[y]"; sleep 1
  setsid nohup python3 camserve.py /dev/video0 640x480@30 2000 75 "$dec" "$enc" > /tmp/camserve.log 2>&1 < /dev/null &
  sleep 15   # MediaMTX і Flight Display перепідключаються
  N=$N bash rm_g2g.sh "${TAG}_${name}" | grep -v -E "^(active|DONE|rc.xml)"
done
pkill -f "camserve.p[y]"; sleep 1
setsid nohup python3 camserve.py > /tmp/camserve.log 2>&1 < /dev/null &
sleep 2; echo "camserve: дефолт (v4l2jpegdec + v4l2h264enc)"; echo DONE
