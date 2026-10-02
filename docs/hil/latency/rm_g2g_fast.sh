#!/bin/bash
# Матриця «від скла до скла» методом «половинки»: перезапуск camserve з варіантом і g2g на кожен. Рядок варіанта:
# "назва декодер_jpeg кодер gop додаткові_controls". Наприкінці — camserve за замовчуванням.
TAG=${1:-fast}; N=${N:-60}
cd ~/latency
VARIANTS=${VARIANTS:-"hwjpeg_hwenc v4l2jpegdec v4l2 75 -
swjpeg_hwenc jpegdec v4l2 75 -
swjpeg_x264 jpegdec x264 75 -
hwjpeg_x264 v4l2jpegdec x264 75 -
hwjpeg_hwenc_cbr v4l2jpegdec v4l2 75 ,video_bitrate_mode=1"}
echo "$VARIANTS" | while read -r name jdec enc gop extra size conv; do
  [ -z "$name" ] && continue; [ "$extra" = "-" ] && extra=""; size=${size:-640x480@30}
  jdec=${jdec//_/ }; conv=${conv:-default}; conv=${conv//_/ }          # «jpegdec_idct-method=ifast» -> «jpegdec idct-method=ifast»
  for p in $(pgrep -x python3); do grep -q camserve /proc/$p/cmdline && kill $p; done; sleep 1
  if [ "$conv" = default ]; then set -- ; else set -- "$conv"; fi
  setsid nohup python3 camserve.py /dev/video0 "$size" 2000 "$gop" "$jdec" "$enc" "$extra" "$@" > /tmp/camserve.log 2>&1 < /dev/null &
  sleep 15
  G2G_PATTERN=halves ROI_ASUS=0.18,0.25,0.45,0.60 ROI_DW=0.74,0.78,0.83,0.90 G2G_RAW=~/latency/${TAG}_${name}.raw N=$N PER=1.0 \
    bash rm_g2g.sh "${TAG}_${name}" | grep -v -E "^(active|DONE|rc.xml)"
done
for p in $(pgrep -x python3); do grep -q camserve /proc/$p/cmdline && kill $p; done; sleep 1
setsid nohup python3 camserve.py /dev/video0 640x480@30 2000 75 jpegdec v4l2 > /tmp/camserve.log 2>&1 < /dev/null &
python3 latpool.py $(ls ${TAG}_*.raw | sort)
echo FIN
