# Від скла до скла БЕЗ композитора (еквівалент DRM lease): labwc зупинено, один процес тримає DRM (/dev/dri/card1) і
# виводить через kmssink на обидва екрани зі спільним fd: спалах «половинки» на ASUS (конектор 35) і плеєр node/sim
# на Daewoo (конектор 44, v4l2h264dec). Аналіз — як g2g.py: потік node/sim, ROI ASUS і Daewoo, різниця кадрів камери.
# sudo -E python3 g2g_kms.py <назва> [N=100] [період=1.0]; env ROI_ASUS, ROI_DW, G2G_URL, G2G_PROTO (udp|tcp)
import os, random, statistics, subprocess, sys, threading, time
import gi
gi.require_version("Gst", "1.0")
from gi.repository import Gst, GLib
name = sys.argv[1]
N = int(sys.argv[2]) if len(sys.argv) > 2 else 100
PER = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
URL = os.environ.get("G2G_URL", "rtsp://10.66.0.1:8554/node/sim")
PROTO = os.environ.get("G2G_PROTO", "udp")
RA = [float(v) for v in os.environ.get("ROI_ASUS", "0.18,0.25,0.45,0.60").split(",")]
RD = [float(v) for v in os.environ.get("ROI_DW", "0.74,0.78,0.83,0.90").split(",")]
Gst.init(None)
fd = os.open("/dev/dri/card1", os.O_RDWR)
DW, DH = 720, 576
CH = b"\x80" * (DW * DH // 2)
L = (b"\xeb" * (DW // 2) + b"\x10" * (DW // 2)) * DH + CH
R = (b"\x10" * (DW // 2) + b"\xeb" * (DW // 2)) * DH + CH
flash = Gst.parse_launch(
    f"appsrc name=src is-live=true format=time caps=video/x-raw,format=I420,width={DW},height={DH},framerate=60/1 ! "
    f"kmssink fd={fd} connector-id=35 can-scale=true render-rectangle=\"<0,0,1920,1080>\" sync=false")
player = Gst.parse_launch(
    f"rtspsrc location={URL} protocols={PROTO} latency=0 drop-on-latency=true ! rtph264depay ! h264parse ! v4l2h264dec ! "
    f"kmssink fd={fd} connector-id=44 can-scale=true render-rectangle=\"<0,0,800,480>\" sync=false")
src = flash.get_by_name("src")
flash.set_state(Gst.State.PLAYING); player.set_state(Gst.State.PLAYING)
loop = GLib.MainLoop(); threading.Thread(target=loop.run, daemon=True).start()
cur = [R]; lock = threading.Lock(); stop = False
def push(data):
    buf = Gst.Buffer.new_wrapped(data); src.emit("push-buffer", buf)
def keeper():
    while not stop:
        with lock: push(cur[0])
        time.sleep(1 / 30)
w, h = 320, 240
cap = subprocess.Popen(["gst-launch-1.0", "-q", "rtspsrc", f"location={URL}", "protocols=tcp", "latency=0", "!", "rtph264depay", "!",
    "h264parse", "!", "avdec_h264", "!", "videoconvert", "!", "videoscale", "!", f"video/x-raw,format=GRAY8,width={w},height={h}",
    "!", "fdsink", "fd=1", "sync=false"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
def box(r): return int(r[0] * w), int(r[1] * h), int(r[2] * w), int(r[3] * h)
BA, BD = box(RA), box(RD)
def mean(b, bx):
    x0, y0, x1, y1 = bx; s = n = 0
    for y in range(y0, y1, 2):
        row = b[y * w + x0:y * w + x1:2]; s += sum(row) / len(row); n += 1
    return s / n
frames = []
def reader():
    i = 0
    while not stop:
        b = bytearray()
        while len(b) < w * h:
            c = cap.stdout.read(w * h - len(b))
            if not c: return
            b += c
        frames.append((time.time(), i, mean(b, BA), mean(b, BD))); i += 1
threading.Thread(target=keeper, daemon=True).start(); threading.Thread(target=reader, daemon=True).start()
time.sleep(8)
toggles, state = [], 0
for k in range(N):
    state ^= 1
    with lock:
        cur[0] = L if state else R
        t0 = time.time(); push(cur[0])
    toggles.append(t0); time.sleep(PER + random.uniform(0, 0.08))
time.sleep(1.0); stop = True; time.sleep(0.3); cap.kill()
flash.set_state(Gst.State.NULL); player.set_state(Gst.State.NULL); loop.quit(); os.close(fd)
def first_cross(col, start_t, base_win, fin_win):
    base = [f[col] for f in frames if base_win[0] <= f[0] <= base_win[1]]
    fin = [f[col] for f in frames if fin_win[0] <= f[0] <= fin_win[1]]
    if not base or not fin: return None
    b, e = statistics.median(base), statistics.median(fin)
    if abs(e - b) < 15: return None
    for f in frames:
        if f[0] > start_t and (f[col] - b) * (e - b) > 0 and abs(f[col] - b) > 0.5 * abs(e - b): return f
    return None
lat = []
for t0 in toggles:
    fa = first_cross(2, t0, (t0 - 0.10, t0 + 0.05), (t0 + PER - 0.25, t0 + PER - 0.02))
    if not fa: continue
    fd_ = first_cross(3, fa[0] - 0.001, (fa[0] - 0.12, fa[0] + 0.02), (t0 + PER - 0.20, t0 + PER - 0.02))
    if not fd_ or fd_[1] <= fa[1]: continue
    lat.append((fd_[0] - fa[0]) * 1000)
if os.environ.get("G2G_RAW"):
    with open(os.environ["G2G_RAW"], "a") as fh: fh.write("".join("%.1f%s" % (v, os.linesep) for v in lat))
if lat:
    s = sorted(lat); q = lambda p: s[min(len(s) - 1, int(p * len(s)))]
    print(f"{name}: n={len(lat)}/{N} mean={statistics.mean(lat):.1f} median={statistics.median(lat):.1f} p10={q(0.1):.1f} p90={q(0.9):.1f} sd={statistics.pstdev(lat):.1f} (arrival-based)")
else:
    print(f"{name}: no detections, frames={len(frames)}")
