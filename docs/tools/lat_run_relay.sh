#!/usr/bin/env bash
# Latency via the relay path (RPi 4 -> VPS relay -> RPi 5 -> FlyByIP-B). Run on the PC (Git Bash).
# Stops the kambala-rc systemd user service on RPi 4, runs lat_pi2 there as the operator
# (source <ws>:1313 -> relay 10.66.0.1:1313), measures with the Betaflight board over USB, then starts kambala-rc again.
# Usage: COM=COM12 [LAT_PERIOD_MS=10] lat_run_relay.sh [samples=30]   (LAT_PERIOD_MS fixes the sender period; empty = follow module SYNC)      (WS_IP defaults to the tunnel address of RPi 4)
set -u; export PYTHONIOENCODING=utf-8
WS_IP="${WS_IP:-10.66.0.3}"; WS="gans@${WS_IP}"; COM="${COM:-COM12}"; N="${1:-30}"
PY="/c/Users/Gans/.venvs/kambala-architect/Scripts/python.exe"; HERE="$(cd "$(dirname "$0")" && pwd)"
stop_all() {
  ssh "$WS" 'systemctl --user stop kambala-rc 2>/dev/null; for p in $(pgrep -f "^python3 .*lat_pi2"); do kill $p 2>/dev/null; done; true'
}
trap 'echo "== відновлюю kambala-rc"; stop_all; ssh "$WS" "systemctl --user start kambala-rc"' EXIT
echo "== зупиняю kambala-rc на RPi 4, запускаю lat_pi2 (оператор -> релей)"; stop_all; sleep 1
ssh "$WS" "LAT_TARGET=10.66.0.1 LAT_SRC=${WS_IP} LAT_PERIOD_MS=${LAT_PERIOD_MS:-} nohup python3 \$HOME/tools/lat_pi2.py 900 0 > /tmp/lat_pi2.log 2>&1 < /dev/null & disown"
sleep 12; ssh "$WS" 'tail -1 /tmp/lat_pi2.log'
echo "== вимір: $N кроків по крену через релей (COM $COM)"; "$PY" "$HERE/lat_pc.py" "$COM" "$WS_IP" "$N" 0 | tail -5
