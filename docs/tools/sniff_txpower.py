#!/usr/bin/env python3
"""Passive sniff of CRSF replies from FlyByIP-B (192.168.13.11:1313) on eth0; prints TX power from LINK_STATISTICS (0x14).
Read-only, sends nothing. Usage: sudo python3 sniff_txpower.py [seconds]"""
import socket, struct, sys, time
SECONDS = float(sys.argv[1]) if len(sys.argv) > 1 else 6.0
PWR = {0: "0mW", 1: "10mW", 2: "25mW", 3: "100mW", 4: "500mW", 5: "1000mW", 6: "2000mW", 7: "250mW", 8: "50mW"}
s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.ntohs(0x0800))
s.bind(("eth0", 0)); s.settimeout(0.5)
t0 = time.time(); seen = {}; n = 0; types = {}
while time.time() - t0 < SECONDS:
    try: pkt = s.recv(2048)
    except socket.timeout: continue
    if len(pkt) < 42: continue
    ihl = (pkt[14] & 0x0F) * 4
    if pkt[23] != 17: continue
    src = ".".join(map(str, pkt[26:30])); sport, dport = struct.unpack("!HH", pkt[14+ihl:14+ihl+4])
    if src != "192.168.13.11" or sport != 1313: continue
    data = pkt[14+ihl+8:]; n += 1; i = 0
    while i + 2 <= len(data):
        ln = data[i+1]
        if ln < 2 or i + 2 + ln > len(data): break
        typ = data[i+2]; types[typ] = types.get(typ, 0) + 1
        if typ == 0x14 and ln >= 12:
            p = data[i+3:i+3+10]; pw = p[6]; seen[pw] = seen.get(pw, 0) + 1
        i += 2 + ln
print(f"packets from FBI-B: {n}; frame types: { {hex(k): v for k, v in types.items()} }")
print("LINK_STATISTICS uplink TX power:", {PWR.get(k, k): v for k, v in seen.items()} or "none seen")
