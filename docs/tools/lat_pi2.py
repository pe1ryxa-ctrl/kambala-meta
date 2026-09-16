#!/usr/bin/env python3
"""Latency sender (RPi). CRSF RC frames 192.168.13.10:1313 -> FlyByIP-B, period follows TX SYNC interval (0x3A/0x10);
module phase requests ignored (PC may shift phase manually). Control UDP :5005: b'go<n>' toggle channel CH next frame
(+'ack'); b'shift<ms>' delay next frame; b'rate<idx>' write Packet Rate (field 1) then READ after 0.3 s and reply
b'rate <value>'; b'ping' -> b'pong <period_ms> <shift>'. Throttle/ARM at minimum. Usage: lat_pi2.py [seconds] [ch]"""
import socket, time, sys, select, struct
import os
FBI = (os.environ.get("LAT_TARGET", "192.168.13.11"), 1313)   # FlyByIP-B directly or relay 10.66.0.1
SRC = (os.environ.get("LAT_SRC", "192.168.13.10"), 1313)      # our source address (must be the module's Remote IP or the relay's operator)
CTRL = ("0.0.0.0", 5005)
SECONDS = float(sys.argv[1]) if len(sys.argv) > 1 else 600.0
CH = int(sys.argv[2]) if len(sys.argv) > 2 else 0
MIN, MID, MAX = 172, 992, 1811
NUL = bytes([0])
def crc8(d):
    c = 0
    for b in d:
        c ^= b
        for _ in range(8): c = ((c << 1) ^ 0xD5) & 0xFF if c & 0x80 else (c << 1) & 0xFF
    return c
def ext_frame(ftype, payload):
    p = bytes([ftype, 0xEE, 0xEA]) + payload
    return bytes([0xEE, len(p) + 1]) + p + bytes([crc8(p)])
def rc_frame(ch):
    bits = n = 0; out = bytearray()
    for v in ch:
        bits |= (v & 0x7FF) << n; n += 11
        while n >= 8: out.append(bits & 0xFF); bits >>= 8; n -= 8
    p = bytes([0x16]) + bytes(out)
    return bytes([0xEE, len(p) + 1]) + p + bytes([crc8(p)])
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(SRC); s.setblocking(False)
c = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); c.bind(CTRL); c.setblocking(False)
ch = [MID] * 16; ch[2] = MIN; ch[4] = MIN; val = MID; ch[CH] = val
period = 0.022866; t0 = time.monotonic(); nxt = t0; n_tx = n_sync = n_go = 0; last_print = t0; shift_total = 0.0
pending = None      # extended frame to send in the next slot instead of RC
rate_req = None     # [t_read_due, addr, attempts]
print(f"lat_pi2: -> {FBI}, follows SYNC interval, ch{CH+1} toggles on 'go'", flush=True)
while time.monotonic() - t0 < SECONDS:
    now = time.monotonic()
    if now >= nxt:
        if pending is not None:
            s.sendto(pending, FBI); pending = None
        else:
            s.sendto(rc_frame(ch), FBI); n_tx += 1
        nxt += period
        if now - nxt > 0.5: nxt = now + period
    if rate_req is not None and now >= rate_req[0]:
        pending = ext_frame(0x2C, bytes([1, 0])); rate_req[0] = now + 0.6; rate_req[2] += 1
        if rate_req[2] > 6: c.sendto(b"rate ? (no reply)", rate_req[1]); rate_req = None
    r, _, _ = select.select([s, c], [], [], max(0.0, min(nxt, rate_req[0] if rate_req else nxt) - time.monotonic()))
    if c in r:
        try:
            data, addr = c.recvfrom(64)
            if data.startswith(b"go"):
                c.sendto(b"ack" + data[2:], addr); val = MAX if val == MID else MID; ch[CH] = val; n_go += 1
            elif data.startswith(b"shift"):
                ms = float(data[5:] or 0); nxt += ms / 1000.0; shift_total += ms; c.sendto(b"ok", addr)
            elif data.startswith(b"rate"):
                idx = int(data[4:]); pending = ext_frame(0x2D, bytes([1, idx])); rate_req = [time.monotonic() + 0.3, addr, 0]
            elif data.startswith(b"ping"):
                c.sendto(b"pong %.3f %.1f" % (period * 1000, shift_total), addr)
        except (BlockingIOError, ValueError): pass
    if s in r:
        try:
            d, _ = s.recvfrom(2048); i = 0
            while i + 2 <= len(d):
                ln = d[i+1]
                if ln < 2 or i + 2 + ln > len(d): break
                if d[i+2] == 0x2B and rate_req is not None and d[i+5] == 1 and d[i+6] == 0:
                    body = d[i+7:i+2+ln-1]              # parent, type, name NUL, options NUL, value, min, max, default, unit NUL
                    z1 = body.find(NUL, 2); z2 = body.find(NUL, z1 + 1) if z1 > 0 else -1
                    if z2 > 0 and z2 + 1 < len(body):
                        c.sendto(b"rate %d" % body[z2 + 1], rate_req[1]); rate_req = None
                if d[i+2] == 0x3A and ln >= 13 and d[i+5] == 0x10:
                    iv = struct.unpack(">I", d[i+6:i+10])[0] / 10_000_000.0
                    if 0.004 < iv < 0.1: period = iv; n_sync += 1
                i += 2 + ln
        except BlockingIOError: pass
    if now - last_print >= 5.0:
        last_print = now; print(f"  t={now-t0:5.0f}s tx={n_tx} sync={n_sync} period={period*1000:.3f}ms shift={shift_total:.1f}ms go={n_go}", flush=True)
