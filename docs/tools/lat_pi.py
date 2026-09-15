#!/usr/bin/env python3
"""Latency test, RPi side. Sends CRSF RC frames at 44 Hz from 192.168.13.10:1313 to FlyByIP-B (throttle/ARM at minimum,
sticks centred). Listens on UDP :5005 for 'go' packets from the PC: replies 'ack' at once (RTT measurement) and toggles
AUX3 (ch7) between 992 and 1811 in the very next frame. Never arms. Usage: lat_pi.py [seconds] (default 300)."""
import socket, time, sys, select
FBI = ("192.168.13.11", 1313); SRC = ("192.168.13.10", 1313); CTRL = ("0.0.0.0", 5005)
SECONDS = float(sys.argv[1]) if len(sys.argv) > 1 else 300.0
CH = int(sys.argv[2]) if len(sys.argv) > 2 else 6   # 0-based channel to toggle (6 = AUX3, 0 = roll)
PERIOD = 0.022866; MIN, MID, MAX = 172, 992, 1811
def crc8(d):
    c = 0
    for b in d:
        c ^= b
        for _ in range(8): c = ((c << 1) ^ 0xD5) & 0xFF if c & 0x80 else (c << 1) & 0xFF
    return c
def rc_frame(ch):
    bits = n = 0; out = bytearray()
    for v in ch:
        bits |= (v & 0x7FF) << n; n += 11
        while n >= 8: out.append(bits & 0xFF); bits >>= 8; n -= 8
    p = bytes([0x16]) + bytes(out)
    return bytes([0xEE, len(p) + 1]) + p + bytes([crc8(p)])
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(SRC); s.setblocking(False)
c = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); c.bind(CTRL); c.setblocking(False)
ch = [MID] * 16; ch[2] = MIN; ch[4] = MIN; aux3 = MID; ch[CH] = aux3
t0 = time.monotonic(); nxt = t0; n_tx = n_rx = n_go = 0; last_print = t0
print(f"lat_pi: {SRC} -> {FBI} @44 Hz, ctrl udp :5005, ARM/throttle min, ch{CH+1} toggles on 'go'", flush=True)
while time.monotonic() - t0 < SECONDS:
    now = time.monotonic()
    if now >= nxt:
        s.sendto(rc_frame(ch), FBI); n_tx += 1; nxt += PERIOD
        if now - nxt > 0.5: nxt = now + PERIOD
    r, _, _ = select.select([s, c], [], [], max(0.0, nxt - time.monotonic()))
    if c in r:
        try:
            data, addr = c.recvfrom(64)
            if data.startswith(b"go"):
                c.sendto(b"ack" + data[2:], addr)
                aux3 = MAX if aux3 == MID else MID; ch[CH] = aux3; n_go += 1
                # send the changed frame immediately AND keep cadence (one early frame is harmless for the module)
                s.sendto(rc_frame(ch), FBI); n_tx += 1; nxt = time.monotonic() + PERIOD
            elif data.startswith(b"ping"):
                c.sendto(b"pong" + data[4:], addr)
        except BlockingIOError: pass
    if s in r:
        try: s.recvfrom(2048); n_rx += 1
        except BlockingIOError: pass
    if now - last_print >= 5.0:
        last_print = now; print(f"  t={now-t0:5.0f}s tx={n_tx} rx={n_rx} go={n_go} aux3={aux3}", flush=True)
print(f"done tx={n_tx} rx={n_rx} go={n_go}")
