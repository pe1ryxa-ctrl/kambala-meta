#!/bin/bash
# Варіанти MediaMTX для шляху node/sim (заміри затримки 02.10). Запуск на VPS (root):
#   bash vps_mtx_variant.sh ondemand yes|no      — sourceOnDemand
#   bash vps_mtx_variant.sh transport tcp|udp    — rtspTransport джерела
#   bash vps_mtx_variant.sh status
#   bash vps_mtx_variant.sh baseline             — sourceOnDemand: yes, rtspTransport: tcp (як було)
# Джерело (source) не чіпає — його перемикає vps_g2g_source.sh. Правка лише блоку node/sim, на місці (той самий inode),
# з копією; після правки — перевірка перечитування або перезапуск mediamtx.
F=/opt/kambala/mediamtx/mediamtx.yml
set_key() { python3 - "$F" "$1" "$2" <<'PY'
import sys, re
p, key, val = sys.argv[1:4]
lines = open(p).read().split("\n")
try:
    i = lines.index("  node/sim:")
except ValueError:
    sys.exit("node/sim: не знайдено")
j = i + 1; found = False
while j < len(lines) and lines[j].startswith("    "):
    if lines[j].strip().startswith(key + ":"):
        lines[j] = "    %s: %s" % (key, val); found = True
    j += 1
if not found:
    lines.insert(j, "    %s: %s" % (key, val))
with open(p, "r+") as fh:
    fh.seek(0); fh.write("\n".join(lines)); fh.truncate()
PY
}
case "$1" in
  status) sed -n '/  node\/sim:/,/^  [a-z]/p' "$F"; exit 0 ;;
  ondemand) [ "$2" = yes ] || [ "$2" = no ] || { echo "yes|no"; exit 2; } ;;
  transport) [ "$2" = tcp ] || [ "$2" = udp ] || { echo "tcp|udp"; exit 2; } ;;
  baseline) ;;
  *) echo "usage: $0 ondemand yes|no | transport tcp|udp | baseline | status"; exit 2 ;;
esac
cp -p "$F" "$F.bak-mtx-$(date +%Y%m%d-%H%M%S)"
case "$1" in
  ondemand) set_key sourceOnDemand "$2" || exit 1 ;;
  transport) set_key rtspTransport "$2" || exit 1 ;;
  baseline) set_key sourceOnDemand yes && set_key rtspTransport tcp || exit 1 ;;
esac
sleep 3
if docker logs --since 10s mediamtx 2>&1 | grep -qi "reload"; then echo "MediaMTX перечитав конфіг"; else echo "перезапуск mediamtx"; docker restart mediamtx >/dev/null && sleep 3; fi
sed -n '/  node\/sim:/,/^  [a-z]/p' "$F"
docker ps --filter name=mediamtx --format '{{.Names}} {{.Status}}'
