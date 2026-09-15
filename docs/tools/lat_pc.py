#!/usr/bin/env python3
"""Latency test, PC side. Polls Betaflight MSP_RC over the FC's USB VCP as fast as possible, sends 'go' to the RPi
every INTERVAL s, and measures time from 'go' until AUX3 (rcData[6]) flips. Subtracts one-way Wi-Fi delay (RTT/2 from
ping/pong). Usage: lat_pc.py COM10 192.168.50.28 [samples]"""
import serial, socket, struct, sys, time, statistics
PORT = sys.argv[1]; PI = (sys.argv[2], 5005); N = int(sys.argv[3]) if len(sys.argv) > 3 else 30
CH = int(sys.argv[4]) if len(sys.argv) > 4 else 6   # MSP_RC index: 0 roll,1 pitch,2 yaw,3 throttle,4 aux1,5 aux2,6 aux3
INTERVAL = 1.5
def msp_req(cmd):
    return b"$M<" + bytes([0, cmd, cmd])
def msp_read(ser, cmd, deadline=0.05):
    ser.reset_input_buffer(); ser.write(msp_req(cmd))
    buf = b""; t_end = time.perf_counter() + deadline
    while time.perf_counter() < t_end:
        buf += ser.read(64)
        i = buf.find(b"$M>")
        if i >= 0 and len(buf) >= i + 5:
            size = buf[i+3]; c = buf[i+4]
            if len(buf) >= i + 5 + size + 1 and c == cmd:
                return buf[i+5:i+5+size]
    return None
ser = serial.Serial(PORT, 115200, timeout=0.002)
time.sleep(0.3)
rc = msp_read(ser, 105)
if rc is None: print("no MSP_RC reply — Betaflight Configurator still connected?"); sys.exit(1)
chans = struct.unpack("<%dH" % (len(rc)//2), rc); print("MSP_RC channels:", chans)
u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); u.settimeout(0.5)
# RTT
rtts = []
for i in range(10):
    t = time.perf_counter(); u.sendto(b"ping%d" % i, PI)
    try:
        d, _ = u.recvfrom(64); rtts.append((time.perf_counter() - t) * 1000)
    except socket.timeout: pass
if not rtts: print("no pong from RPi — lat_pi.py running?"); sys.exit(1)
rtt = statistics.median(rtts); print(f"wifi RTT median {rtt:.1f} ms (n={len(rtts)}) -> one-way {rtt/2:.1f} ms")
def aux3():
    r = msp_read(ser, 105)
    return None if r is None else struct.unpack("<%dH" % (len(r)//2), r)[CH]
lat = []; polls = 0
for k in range(N):
    base = aux3()
    if base is None: continue
    t_go = time.perf_counter(); u.sendto(b"go%d" % k, PI)
    got = False
    while time.perf_counter() - t_go < 1.0:
        v = aux3(); polls += 1
        if v is not None and abs(v - base) > 200:
            t = (time.perf_counter() - t_go) * 1000 - rtt / 2
            lat.append(t); print(f"  #{k:2d} aux3 {base} -> {v}: {t:6.1f} ms", flush=True); got = True; break
    if not got: print(f"  #{k:2d} no change within 1 s (base {base})", flush=True)
    time.sleep(INTERVAL)
if lat:
    lat.sort(); n = len(lat)
    print(f"\nRESULT n={n}: min {lat[0]:.1f}  median {statistics.median(lat):.1f}  p90 {lat[int(0.9*(n-1))]:.1f}  max {lat[-1]:.1f} ms  "
          f"(MSP poll ~{1000*N/ max(polls,1):.1f}? see rate below)")
    print(f"MSP polls total {polls}")
