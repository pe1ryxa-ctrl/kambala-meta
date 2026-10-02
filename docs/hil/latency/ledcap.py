# Затримка «світло перед камерою -> кадр у процесі»: світлодіод Caps Lock -> аналогова камера -> V399 -> декодер JPEG.
# Один годинник РМ-1. camserve має бути зупинено (V399 вільний). python3 ledcap.py <brightness> <ROI x0,y0,x1,y1> [N=100] [декодер=jpegdec]
import os, random, shlex, statistics, subprocess, sys, threading, time
LED, R = sys.argv[1], [float(v) for v in sys.argv[2].split(",")]
N = int(sys.argv[3]) if len(sys.argv) > 3 else 100
DEC = sys.argv[4] if len(sys.argv) > 4 else "jpegdec"
w, h = 640, 480
cap = subprocess.Popen(["gst-launch-1.0", "-q", "v4l2src", "device=/dev/video0", "!", "image/jpeg,width=640,height=480,framerate=30/1", "!",
    "queue", "max-size-buffers=1", "leaky=downstream", "!"] + shlex.split(DEC) + ["!", "videoconvert", "!",
    f"video/x-raw,format=GRAY8,width={w},height={h}", "!", "fdsink", "fd=1", "sync=false"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
x0, y0, x1, y1 = int(R[0] * w), int(R[1] * h), int(R[2] * w), int(R[3] * h)
frames, stop = [], False
def reader():
    while not stop:
        b = bytearray()
        while len(b) < w * h:
            c = cap.stdout.read(w * h - len(b))
            if not c: return
            b += c
        t = time.time(); s = n = 0
        for y in range(y0, y1):
            row = b[y * w + x0:y * w + x1]; s += sum(row) / len(row); n += 1
        frames.append((t, s / n))
threading.Thread(target=reader, daemon=True).start()
time.sleep(3)
tog, st = [], 0
for k in range(N):
    st ^= 1; t0 = time.time()
    with open(LED, "w") as fh: fh.write(str(st))
    tog.append(t0); time.sleep(0.5 + random.uniform(0, 0.08))
time.sleep(0.5); stop = True; cap.kill()
with open(LED, "w") as fh: fh.write("0")
lat = []
for t0 in tog:
    base = [v for t, v in frames if t0 - 0.10 <= t <= t0]
    fin = [v for t, v in frames if t0 + 0.30 <= t <= t0 + 0.48]
    if not base or not fin: continue
    b, e = statistics.median(base), statistics.median(fin)
    if abs(e - b) < 10: continue
    for t, v in frames:
        if t > t0 and (v - b) * (e - b) > 0 and abs(v - b) > 0.5 * abs(e - b): lat.append((t - t0) * 1000); break
if lat:
    s = sorted(lat); q = lambda p: s[min(len(s) - 1, int(p * len(s)))]
    print(f"ledcap {DEC}: n={len(lat)}/{N} mean={statistics.mean(lat):.1f} median={statistics.median(lat):.1f} p10={q(0.1):.1f} p90={q(0.9):.1f} min={s[0]:.1f}")
else:
    print(f"ledcap: no detections, frames={len(frames)}")
