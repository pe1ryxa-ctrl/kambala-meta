# Від скла до скла (KWS-044, ідея Gans 02.10): РМ блимає на ASUS (екран штурмана) -> камера -> V399 на sim ->
# кодер sim -> VPS (MediaMTX) -> РМ -> Flight Display на Daewoo (пілот). Камера бачить ОБИДВА екрани, тож затримка
# рахується з тих самих кадрів камери: від кадру, де спалахнув ASUS, до кадру, де спалахнув Daewoo. Годинники не потрібні.
# Кадри камери беремо з потоку node/sim на РМ (другий клієнт MediaMTX) — обидві області в одному кадрі, затримка доставки
# на результат не впливає. Крок кадру камери 40 мс (25 к/с); при випадковій фазі середнє різниць незміщене.
# python3 g2g.py <назва> [N=200] [період_с=1.0]; env: G2G_URL, ROI_ASUS, ROI_DW (частки кадру камери), G2G_DEC
import os, random, shlex, statistics, subprocess, sys, threading, time
name = sys.argv[1]
N = int(sys.argv[2]) if len(sys.argv) > 2 else 200
PER = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
URL = os.environ.get("G2G_URL", "rtsp://10.66.0.1:8554/node/sim")
DEC = os.environ.get("G2G_DEC", "avdec_h264")
FRAME_MS = float(os.environ.get("G2G_FRAME_MS", "40"))
def roi(env, default):
    return [float(v) for v in os.environ.get(env, default).split(",")]
RA, RD = roi("ROI_ASUS", "0.15,0.25,0.60,0.60"), roi("ROI_DW", "0.70,0.74,0.96,0.95")
# спалах на ASUS: gst-launch-1.0 (правило labwc тимчасово шле його на HDMI-A-1 — див. rm_g2g.sh)
DW, DH = 720, 576
CH = b"\x80" * (DW * DH // 2)
WHITE, BLACK = b"\xeb" * (DW * DH) + CH, b"\x10" * (DW * DH) + CH
disp = subprocess.Popen(["gst-launch-1.0", "-q", "fdsrc", "fd=0", f"blocksize={len(WHITE)}", "!", "rawvideoparse", "format=i420",
    f"width={DW}", f"height={DH}", "framerate=60/1", "!", "videoconvert", "!", "waylandsink", "sync=false"],
    stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
w, h = 320, 240
cap = subprocess.Popen(["gst-launch-1.0", "-q", "rtspsrc", f"location={URL}", "protocols=tcp", "latency=0", "!", "rtph264depay", "!",
    "h264parse", "!"] + shlex.split(DEC) + ["!", "videoconvert", "!", "videoscale", "!", f"video/x-raw,format=GRAY8,width={w},height={h}",
    "!", "fdsink", "fd=1", "sync=false"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
def box(r):
    return int(r[0] * w), int(r[1] * h), int(r[2] * w), int(r[3] * h)
BA, BD = box(RA), box(RD)
def mean(b, bx):
    x0, y0, x1, y1 = bx; s = n = 0
    for y in range(y0, y1, 2):
        row = b[y * w + x0:y * w + x1:2]; s += sum(row) / len(row); n += 1
    return s / n
frames, stop, cur = [], False, [BLACK]   # (t_arrival, idx, A, D)
lock = threading.Lock()
def reader():
    i = 0
    while not stop:
        b = bytearray()
        while len(b) < w * h:
            c = cap.stdout.read(w * h - len(b))
            if not c: return
            b += c
        frames.append((time.time(), i, mean(b, BA), mean(b, BD))); i += 1
def keeper():
    while not stop:
        with lock: disp.stdin.write(cur[0]); disp.stdin.flush()
        time.sleep(1 / 30)
threading.Thread(target=reader, daemon=True).start(); threading.Thread(target=keeper, daemon=True).start()
time.sleep(6)                                  # підключення до RTSP + ключовий кадр
toggles, state = [], 0
for k in range(N):
    state ^= 1
    with lock:
        cur[0] = WHITE if state else BLACK
        t0 = time.time(); disp.stdin.write(cur[0]); disp.stdin.flush()
    toggles.append(t0)
    time.sleep(PER + random.uniform(0, 0.08))
time.sleep(1.0); stop = True; time.sleep(0.3); cap.kill(); disp.kill()
def first_cross(seq, col, start_t, base_win, fin_win):
    base = [f[col] for f in seq if base_win[0] <= f[0] <= base_win[1]]
    fin = [f[col] for f in seq if fin_win[0] <= f[0] <= fin_win[1]]
    if not base or not fin: return None
    b, e = statistics.median(base), statistics.median(fin)
    if abs(e - b) < 15: return None
    for f in seq:
        if f[0] > start_t and abs(f[col] - b) > 0.5 * abs(e - b): return f
    return None
lat, arr = [], []
for t0 in toggles:
    fa = first_cross(frames, 2, t0, (t0 - 0.10, t0 + 0.05), (t0 + PER - 0.25, t0 + PER - 0.02))
    if not fa: continue
    # Daewoo: базовий рівень — кадри навколо спалаху ASUS (Daewoo ще показує старе), кінцевий — перед наступним спалахом
    fd = first_cross(frames, 3, fa[0] - 0.001, (fa[0] - 0.12, fa[0] + 0.02), (t0 + PER - 0.20, t0 + PER - 0.02))
    if not fd or fd[1] <= fa[1]: continue
    lat.append((fd[1] - fa[1]) * FRAME_MS); arr.append((fd[0] - fa[0]) * 1000)
fr = [f[0] for f in frames]
fps = len([1 for t in fr if fr[0] + 3 <= t <= fr[0] + 13]) / 10.0 if fr else 0
if os.environ.get("G2G_RAW"):
    with open(os.environ["G2G_RAW"], "a") as fh:
        fh.write("".join("%.1f%s" % (v, os.linesep) for v in lat))
if lat:
    s = sorted(lat); q = lambda p: s[min(len(s) - 1, int(p * len(s)))]
    print(f"{name}: n={len(lat)}/{N} mean={statistics.mean(lat):.1f} median={statistics.median(lat):.1f} "
          f"p10={q(0.1):.1f} p90={q(0.9):.1f} sd={statistics.pstdev(lat):.1f} | arrival_diff_mean={statistics.mean(arr):.1f} fps_stream={fps:.1f}")
else:
    print(f"{name}: no detections, frames={len(frames)} fps_stream={fps:.1f}")
