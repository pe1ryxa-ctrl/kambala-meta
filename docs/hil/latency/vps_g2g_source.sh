#!/bin/bash
# Тимчасово перемкнути джерело MediaMTX node/sim: RPi 5 (10.66.0.10) <-> РМ-1 (10.66.0.3) для заміру «від скла до скла».
# Запуск на VPS (root): bash vps_g2g_source.sh rm1 | restore | status
# Файл змонтовано в контейнер як окремий файл: правимо НА МІСЦІ (той самий inode), інакше контейнер не побачить змін.
F=/opt/kambala/mediamtx/mediamtx.yml
SIM='rtsp://10.66.0.10:8554/video0'; RM1='rtsp://10.66.0.3:8554/video0'
case "$1" in
  rm1) FROM=$SIM; TO=$RM1 ;;
  restore) FROM=$RM1; TO=$SIM ;;
  status) grep -n -A1 'node/sim:' "$F"; exit 0 ;;
  *) echo "usage: $0 rm1|restore|status"; exit 2 ;;
esac
grep -q "source: $TO" "$F" && { echo "вже: $TO"; exit 0; }
[ "$(grep -c "source: $FROM" "$F")" = 1 ] || { echo "не знайдено рівно одне 'source: $FROM' — нічого не змінено"; exit 1; }
cp -p "$F" "$F.bak-g2g-$(date +%Y%m%d-%H%M%S)"
python3 - "$F" "$FROM" "$TO" <<'PY'
import sys
p, a, b = sys.argv[1:4]
s = open(p).read()
with open(p, "r+") as fh:          # на місці: truncate + write, inode той самий
    fh.seek(0); fh.write(s.replace("source: " + a, "source: " + b)); fh.truncate()
PY
sleep 3
if docker logs --since 10s mediamtx 2>&1 | grep -qi "reload"; then echo "MediaMTX перечитав конфіг"; else echo "автоперечитування не видно — перезапуск mediamtx"; docker restart mediamtx >/dev/null && sleep 3; fi
grep -n -A1 'node/sim:' "$F"
docker ps --filter name=mediamtx --format '{{.Names}} {{.Status}}'
