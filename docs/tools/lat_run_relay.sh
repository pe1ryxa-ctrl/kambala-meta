#!/usr/bin/env bash
# Latency via the relay path (RPi 4 -> VPS relay -> RPi 5 -> FlyByIP-B). Run on the PC (Git Bash).
# Stops rc on RPi 4, runs lat_pi2 there as the operator (source 10.66.0.3:1313 -> relay 10.66.0.1:1313),
# measures with the Betaflight board over USB, then restarts rc. Usage: lat_run_relay.sh [samples=30]
set -u; export PYTHONIOENCODING=utf-8
WS=gans@kambala-ws.local; WS_IP="$(ssh gans@kambala-ws.local "hostname -I | cut -d\" \" -f1")"; COM=COM10; N="${1:-30}"
PY="/c/Users/Gans/.venvs/kambala-architect/Scripts/python.exe"; HERE="$(cd "$(dirname "$0")" && pwd)"
RC_START='cd ~/kws && PYTHONPATH=~/kws/src nohup .venv/bin/python -m kambala_ws.rc > /tmp/rc_run.log 2>&1 < /dev/null & disown'
stop_all() { ssh $WS 'for p in $(pgrep -f "python -m kambala_ws.rc|^python3 .*lat_pi2"); do kill $p 2>/dev/null; done; true'; }
echo "== зупиняю rc на RPi 4, запускаю lat_pi2 (оператор -> релей)"; stop_all; sleep 1
ssh $WS 'LAT_TARGET=10.66.0.1 LAT_SRC=10.66.0.3 nohup python3 $HOME/tools/lat_pi2.py 900 0 > /tmp/lat_pi2.log 2>&1 < /dev/null & disown'
sleep 12; ssh $WS 'tail -1 /tmp/lat_pi2.log'
echo "== вимір: $N кроків по крену через релей"; "$PY" "$HERE/lat_pc.py" $COM $WS_IP $N 0 | tail -5
echo "== відновлюю rc на RPi 4"; stop_all; ssh $WS "$RC_START"; echo "готово"
