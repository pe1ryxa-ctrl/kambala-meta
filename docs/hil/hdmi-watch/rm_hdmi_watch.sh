#!/usr/bin/env bash
# Kambala: сторож зникнення HDMI-входу Streamer вузла hil (30.09, вдруге за день).
# Раз на 2 с знімає стан входів Streamer (через devices API сервера, як це робить РМ) і стан РМ;
# у журнал пише лише ЗМІНИ + пульс раз на 10 хв. Нічого не змінює.
# Запуск на РМ (переживає вихід із SSH, не переживає перезавантаження РМ):
#   systemd-run --user --unit=kambala-hdmi-watch bash ~/hdmi-watch/rm_hdmi_watch.sh
# Журнал: ~/hdmi-watch/hdmi-watch.log · Зупинка: systemctl --user stop kambala-hdmi-watch
set -u
D="$HOME/hdmi-watch"; LOG="$D/hdmi-watch.log"; mkdir -p "$D"
API="${HDMI_WATCH_API:-http://10.66.0.1:8002/nodes/hil/devices/streamer}"
prev=""; last_beat=0
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }
log "START api=$API boot=$(cut -c1-8 /proc/sys/kernel/random/boot_id)"
while :; do
  s=$(curl -s -m 3 "$API" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print("api=ERR"); sys.exit()
if not d.get("available"):
    print("streamer=UNAVAILABLE err=%s" % d.get("error")); sys.exit()
out = ["active=%s" % d.get("active_input_id")]
for i in d.get("inputs", []):
    out.append("in%s[en=%d live=%d dev=%d]" % (i["id"], bool(i.get("enabled")), bool(i.get("live")), bool(i.get("device_available"))))
print(" ".join(out))' 2>/dev/null)
  rm=""
  for f in /sys/class/drm/card*-HDMI-A-*/status; do n=${f#*card?-}; rm="$rm ${n%/status}=$(cat "$f")"; done
  rm="$rm display=$(systemctl --user is-active kambala-display 2>/dev/null)"
  cur="$s |$rm"
  if [ "$cur" != "$prev" ]; then log "CHANGE $cur"; prev="$cur"; fi
  now=$(date +%s); if [ $((now - last_beat)) -ge 600 ]; then log "BEAT $cur"; last_beat=$now; fi
  sleep 2
done
