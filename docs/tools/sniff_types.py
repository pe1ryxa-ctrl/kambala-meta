#!/usr/bin/env python3
"""Count CRSF frame types per direction on eth0 udp 1313 for N seconds (ETH_P_ALL: both directions);
dump every extended/param frame in full hex. Read-only."""
import socket, struct, sys, time
SECONDS = float(sys.argv[1]) if len(sys.argv) > 1 else 20.0
s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.ntohs(0x0003)); s.bind(("eth0", 0)); s.settimeout(0.2)
t0 = time.time(); cnt = {}; dg = {}
while time.time() - t0 < SECONDS:
    try: pkt = s.recv(2048)
    except socket.timeout: continue
    if len(pkt) < 42 or pkt[12:14] != bytes([8, 0]) or pkt[23] != 17: continue
    ihl = (pkt[14] & 0x0F) * 4
    src = ".".join(map(str, pkt[26:30])); dst = ".".join(map(str, pkt[30:34]))
    sport, dport = struct.unpack("!HH", pkt[14+ihl:14+ihl+4])
    if {src, dst} != {"192.168.13.10", "192.168.13.11"} or 1313 not in (sport, dport): continue
    d = "rc->FBI" if src.endswith(".10") else "FBI->rc"
    ulen = struct.unpack("!H", pkt[14+ihl+4:14+ihl+6])[0] - 8
    data = pkt[14+ihl+8:14+ihl+8+ulen]; dg[d] = dg.get(d, 0) + 1
    i = 0
    while i + 2 <= len(data):
        ln = data[i+1]
        if ln < 2 or i + 2 + ln > len(data):
            cnt[(d, "BADLEN")] = cnt.get((d, "BADLEN"), 0) + 1; break
        typ = data[i+2]; cnt[(d, hex(typ))] = cnt.get((d, hex(typ)), 0) + 1
        if typ not in (0x16, 0x14, 0x3a, 0x08, 0x1e, 0x21, 0x02, 0x07):
            print(f"{time.strftime('%H:%M:%S')} {d} type={hex(typ)} len={ln} frame={data[i:i+2+ln].hex()}", flush=True)
        i += 2 + ln
print("datagrams:", dg); print("frames:", {f"{k[0]} {k[1]}": v for k, v in sorted(cnt.items())})
