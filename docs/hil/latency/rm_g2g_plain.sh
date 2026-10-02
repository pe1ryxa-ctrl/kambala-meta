#!/bin/bash
# «Від скла до скла» з мінімальним плеєром замість Flight Display: чи додає затримку сам процес kambala-display.
# Зупиняє kambala-display, запускає gst-launch на Daewoo (штатне правило labwc gst-launch-1.0 -> HDMI-A-2), g2g, відновлення.
TAG=${1:-g2gp}; N=${N:-100}; DEC=${DEC:-v4l2h264dec}; PROTO=${PROTO:-udp}
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0
cd ~/latency
systemctl --user stop kambala-display; sleep 2
setsid nohup gst-launch-1.0 rtspsrc location=rtsp://10.66.0.1:8554/node/sim protocols=$PROTO latency=0 drop-on-latency=true \
  ! rtph264depay ! h264parse ! $DEC ! videoconvert ! waylandsink sync=false > /tmp/plainplayer.log 2>&1 < /dev/null &
sleep 8
N=$N bash rm_g2g.sh "$TAG" | grep -v -E "^(active|DONE)"
pkill -f "rtspsrc location=rtsp://10.66.0.1:8554/node/si[m]"; sleep 1
systemctl --user start kambala-display; sleep 3; systemctl --user is-active kambala-display; echo DONE
