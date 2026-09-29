#!/bin/bash
# Kambala 2026-09-29, HIL KSRV-017: place test releases hil017 0.0.1 (unsigned) and 0.0.2 (signed by
# gans-master-1) into the releases volume, then ask the server to recommend each one.
# Expected: 0.0.1 refused (no valid signature), 0.0.2 accepted. Component hil017 is a dummy, no device uses it.
set -u
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
SRC=$(dirname "$(find /tmp/hil017 -name 'hil017-0.0.2.tgz' | head -1)")
[ -f "$SRC/hil017-0.0.1.tgz" ] && [ -f "$SRC/hil017-0.0.2.tgz.sig" ] || { echo "FAIL: files not found under /tmp/hil017"; exit 1; }
VOL=$(docker volume inspect kambala_releases_data --format '{{.Mountpoint}}')
echo "== volume $VOL, files from $SRC"
for v in 0.0.1 0.0.2; do
  mkdir -p "$VOL/hil017/$v"
  cp "$SRC"/hil017-$v.tgz* "$VOL/hil017/$v/"
  cp "$SRC/hil017-$v-release.json" "$VOL/hil017/$v/release.json"
done
chown -R 10001:999 "$VOL/hil017"
ls -ln "$VOL/hil017"/*
rec() {
  echo "== recommend $1"
  curl -s -m 10 -w '\nHTTP %{http_code}\n' -X POST http://127.0.0.1:8003/releases/hil017/recommend \
    -H 'Content-Type: application/json' \
    -d "{\"version\":\"$1\",\"confirm\":true,\"reason\":\"HIL KSRV-017 $2\"}"
}
rec 0.0.1 "unsigned - expect refusal"
rec 0.0.2 "signed by gans-master-1 - expect accept"
echo "== latest.json"
curl -s -m 5 http://127.0.0.1:8003/releases/hil017/latest.json | head -c 400; echo
echo "== releases log"
docker logs --since 3m releases 2>&1 | grep -i -E "recommend|signature|hil017" | tail -6
echo "== DONE"
