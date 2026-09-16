#!/usr/bin/env python3
"""Latency test, PC side, for ArduPilot flight controllers (MAVLink over USB).
Polls RC_CHANNELS (requests it at 100 Hz via SET_MESSAGE_INTERVAL), sends 'go' to the RPi sender
(lat_pi2.py) every INTERVAL s and measures the time until channel CH flips. Subtracts one-way Wi-Fi delay (RTT/2).
Usage: lat_pc_mav.py COM10 192.168.50.28 [samples=30] [ch=1]   (ch is 1-based RC channel: 1 roll ... 7 AUX3)"""
import socket, sys, time, statistics
from pymavlink import mavutil

PORT = sys.argv[1]; PI = (sys.argv[2], 5005)
N = int(sys.argv[3]) if len(sys.argv) > 3 else 30
CH = int(sys.argv[4]) if len(sys.argv) > 4 else 1
INTERVAL = 1.5

m = mavutil.mavlink_connection(PORT, baud=115200)
m.wait_heartbeat(timeout=10)
print(f"heartbeat from sys {m.target_system} comp {m.target_component}")
# ask for RC_CHANNELS (id 65) every 10 ms
m.mav.command_long_send(m.target_system, m.target_component, mavutil.mavlink.MAV_CMD_SET_MESSAGE_INTERVAL, 0,
                        65, 10000, 0, 0, 0, 0, 0)

def chan():
    msg = m.recv_match(type="RC_CHANNELS", blocking=True, timeout=0.5)
    return None if msg is None else getattr(msg, f"chan{CH}_raw")

u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); u.settimeout(0.5)
rtts = []
for i in range(10):
    t = time.perf_counter(); u.sendto(b"ping", PI)
    try:
        u.recvfrom(64); rtts.append((time.perf_counter() - t) * 1000)
    except socket.timeout:
        pass
if not rtts:
    print("no pong from RPi — lat_pi2.py running?"); sys.exit(1)
rtt = statistics.median(rtts); print(f"wifi RTT median {rtt:.1f} ms -> one-way {rtt/2:.1f} ms")
print("RC_CHANNELS chan%d now: %s" % (CH, chan()))
lat = []; polls = 0
for k in range(N):
    base = chan()
    if base is None:
        print("  no RC_CHANNELS"); continue
    t_go = time.perf_counter(); u.sendto(b"go%d" % k, PI); got = False
    while time.perf_counter() - t_go < 1.0:
        v = chan(); polls += 1
        if v is not None and abs(v - base) > 200:
            t = (time.perf_counter() - t_go) * 1000 - rtt / 2
            lat.append(t); print(f"  #{k:2d} ch{CH} {base} -> {v}: {t:6.1f} ms", flush=True); got = True; break
    if not got:
        print(f"  #{k:2d} no change within 1 s (base {base})", flush=True)
    time.sleep(INTERVAL)
if lat:
    lat.sort(); n = len(lat)
    print(f"\nRESULT n={n}: min {lat[0]:.1f}  median {statistics.median(lat):.1f}  p90 {lat[int(0.9*(n-1))]:.1f}  max {lat[-1]:.1f} ms")
    print(f"RC_CHANNELS polls total {polls}")
