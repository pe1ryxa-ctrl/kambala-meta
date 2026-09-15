#!/usr/bin/env bash
# Latency test orchestrator (PC, Git Bash). Usage: lat_run.sh [rate_idx]   (0=14Hz 1=25Hz 2=44Hz 3=82Hz; omit = keep)
set -u
PI=gans@kambala-sim.local; PI_IP=192.168.50.28; COM=COM10; N=30
export PYTHONIOENCODING=utf-8; PY="/c/Users/Gans/.venvs/kambala-architect/Scripts/python.exe"; HERE="$(cd "$(dirname "$0")" && pwd)"
RATE="${1:-}"
stop_all() { ssh $PI 'for p in $(pgrep -f "^/home/gans/kambala/node-sim/.venv/bin/python -m kambala_ws.rc|^python3 /tmp/lat_pi"); do kill $p 2>/dev/null; done; true'; }
echo "== зупиняю rc/сендери, запускаю lat_pi2 (крен)"; stop_all; sleep 1
ssh $PI 'nohup python3 /tmp/lat_pi2.py 900 0 > /tmp/lat_pi2.log 2>&1 < /dev/null & disown'
echo "== чекаю TX (до 60 с)"
for i in $(seq 1 30); do ssh $PI 'sudo -n python3 /tmp/sniff_txpower.py 2' | grep -q "TX power: {" && { echo "TX відповідає"; break; }; sleep 2; done
if [ -n "$RATE" ]; then
  echo "== ставлю Packet Rate idx $RATE (WRITE поле 1, READ через 0.3 с)"
  "$PY" - "$PI_IP" "$RATE" <<'PYEOF'
import socket, sys, time
u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); u.settimeout(6)
for attempt in range(4):
    u.sendto(b"rate%s" % sys.argv[2].encode(), (sys.argv[1], 5005))
    try:
        r = u.recvfrom(64)[0].decode(); print("модуль:", r)
        if r.split()[-1] == sys.argv[2]: break
    except socket.timeout: print("немає відповіді")
    time.sleep(1)
PYEOF
  echo "== чекаю 15 с, поки лінк перевстановиться на новому темпі"; sleep 15; ssh $PI 'tail -1 /tmp/lat_pi2.log'
fi
echo "== вимір: $N кроків по крену"; "$PY" "$HERE/lat_pc.py" $COM $PI_IP $N 0 | tail -5
echo "== зупиняю сендер"; stop_all; echo "готово"
