#!/usr/bin/env python3
"""Per-hop video latency probe. Pulls an RTSP stream with ffmpeg (low-delay, software decode),
stamps every decoded frame with the local wall clock at arrival and saves a grayscale crop
(the area with a burnt-in clock) as PNG named <prefix>_<n>_<HHMMSS.mmm UTC>.png.
Compare the clock inside the crop with the time in the file name -> latency up to this host.
Env FS_TRANSPORT=tcp|udp selects the RTSP transport (default tcp).
Usage: framestamp.py URL WIDTH HEIGHT X Y W H [saves=6] [every=30] [prefix=/tmp/fs]"""
import os, struct, subprocess, sys, time, zlib
from datetime import datetime, timezone

url = sys.argv[1]
fw, fh, cx, cy, cw, ch = map(int, sys.argv[2:8])
saves = int(sys.argv[8]) if len(sys.argv) > 8 else 6
every = int(sys.argv[9]) if len(sys.argv) > 9 else 30
prefix = sys.argv[10] if len(sys.argv) > 10 else "/tmp/fs"


def write_png(path, w, h, gray):
    raw = b"".join(b"\x00" + gray[y * w:(y + 1) * w] for y in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


cmd = ["ffmpeg", "-loglevel", "error", "-fflags", "nobuffer", "-flags", "low_delay", "-rtsp_transport", os.environ.get("FS_TRANSPORT", "tcp"),
       "-i", url, "-an", "-vf", f"scale={fw}:{fh}", "-pix_fmt", "gray", "-f", "rawvideo", "-"]
p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
size = fw * fh
n = saved = 0
while saved < saves:
    buf = p.stdout.read(size)
    if len(buf) < size:
        break
    t = time.time()
    n += 1
    if n > 60 and n % every == 0:          # skip start-up burst
        crop = b"".join(buf[(cy + y) * fw + cx:(cy + y) * fw + cx + cw] for y in range(ch))
        stamp = datetime.fromtimestamp(t, timezone.utc).strftime("%H%M%S.%f")[:10]
        write_png(f"{prefix}_{saved}_{stamp}.png", cw, ch, crop)
        saved += 1
p.kill()
print(f"frames {n}, saved {saved}")
