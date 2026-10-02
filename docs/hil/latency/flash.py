# KWS-044: спалахи fb RPi 5 -> камера -> V399 -> [кодер sim -> RTSP -> ...] -> декодер на RPi 5. Один годинник.
import random, os, subprocess, sys, threading, time, statistics, shlex
name, head = sys.argv[1], sys.argv[2]
N = int(sys.argv[3]) if len(sys.argv) > 3 else 40
PER = float(sys.argv[4]) if len(sys.argv) > 4 else 0.8
w, h = 320, 240
H, STRIDE = 1080, 3840
fb = os.open("/dev/fb0", os.O_RDWR)
BLACK, WHITE = bytes(STRIDE * H), b"\xff" * (STRIDE * H)
cmd = ["gst-launch-1.0", "-q"] + shlex.split(head) + ["!", "videoconvert", "!", "videoscale", "!",
       f"video/x-raw,format=GRAY8,width={w},height={h}", "!", "fdsink", "fd=1", "sync=false"]
p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
size = w * h
frames = []
stop = False
def reader():
    while not stop:
        b = bytearray()
        while len(b) < size:
            c = p.stdout.read(size - len(b))
            if not c: return
            b += c
        t = time.time()
        s, n = 0, 0
        for y in range(h // 4, 3 * h // 4, 2):
            row = b[y * w + w // 4:y * w + 3 * w // 4:2]
            s += sum(row) / len(row); n += 1
        frames.append((t, s / n))
th = threading.Thread(target=reader, daemon=True); th.start()
os.pwrite(fb, BLACK, 0); time.sleep(4)
toggles = []
state = 0
for i in range(N):
    state ^= 1
    t0 = time.time()
    os.pwrite(fb, WHITE if state else BLACK, 0)
    toggles.append(t0)
    time.sleep(PER + random.uniform(0, 0.08))
stop = True; time.sleep(0.3); p.kill()
lat = []
for tt in toggles:
    base = [v for t, v in frames if tt - 0.15 <= t <= tt]
    fin = [v for t, v in frames if tt + PER - 0.2 <= t <= tt + PER - 0.01]
    if not base or not fin: continue
    b, f = statistics.median(base), statistics.median(fin)
    if abs(f - b) < 20: continue
    for t, v in frames:
        if t > tt and abs(v - b) > 0.5 * abs(f - b):
            lat.append((t - tt) * 1000); break
lat.sort()
fr = [t for t, _ in frames]
fps_real = len([1 for t in fr if fr[0] + 3 <= t <= fr[0] + 13]) / 10.0 if fr else 0
if lat:
    q = lambda k: lat[min(len(lat) - 1, int(k * len(lat)))]
    print(f"{name}: n={len(lat)}/{N} median={statistics.median(lat):.1f} p10={q(0.1):.1f} p90={q(0.9):.1f} min={lat[0]:.1f} max={lat[-1]:.1f} fps_real={fps_real:.1f}")
else:
    print(f"{name}: no detections, frames={len(frames)}")
