# Спалахи на екрані РМ (waylandsink, справжній композитор) -> камера -> V399 на цьому ж РМ -> декодер. Один годинник.
# python3 rmflash.py <назва> <пристрій V399> [N=40] [період_с=0.8] [WxH@fps захоплення=640x480@30] [декодер=jpegdec]
import os, random, shlex, statistics, subprocess, sys, threading, time
name, dev = sys.argv[1], sys.argv[2]
N = int(sys.argv[3]) if len(sys.argv) > 3 else 40
PER = float(sys.argv[4]) if len(sys.argv) > 4 else 0.8
cw, rest = (sys.argv[5] if len(sys.argv) > 5 else "640x480@30").split("x"); ch, cf = rest.split("@")
dec = sys.argv[6] if len(sys.argv) > 6 else "jpegdec"
FMT = os.environ.get("RMFLASH_FMT", "gray8")   # gray8 320x180 або i420 720x576 (як відео вузла)
DW, DH = (720, 576) if FMT == "i420" else (320, 180)
if os.environ.get("RMFLASH_SIZE"):                  # напр. 800x480 — рідний розмір екрана, без масштабування
    DW, DH = (int(v) for v in os.environ["RMFLASH_SIZE"].split("x"))
KEEP_HZ = float(os.environ.get("RMFLASH_KEEP_HZ", "30"))  # для великих кадрів менше — щоб труба встигала                    # кадр спалаху; gst-launch-1.0 правило labwc шле на KWS_DISPLAY_OUTPUT (пілот); RMFLASH_GST=/tmp/kflash (symlink) — вікно на виводі з фокусом (UI, ASUS) на весь екран
CH = b"\x80" * (DW * DH // 2) if FMT == "i420" else b""   # площини U/V для I420
WHITE, BLACK = b"\xeb" * (DW * DH) + CH, b"\x10" * (DW * DH) + CH
DISP_BIN = os.environ.get("RMFLASH_GST", "gst-launch-1.0")  # інше ім'я -> правило labwc для gst-launch-1.0 не діє
disp = subprocess.Popen([DISP_BIN, "-q", "fdsrc", "fd=0", f"blocksize={len(WHITE)}", "!",
    f"rawvideoparse", f"format={FMT}", f"width={DW}", f"height={DH}", "framerate=60/1", "!",
    "videoconvert", "!"] + (shlex.split(os.environ["RMFLASH_SINK"]) if os.environ.get("RMFLASH_SINK") else ["waylandsink"] + (["fullscreen=true"] if DISP_BIN != "gst-launch-1.0" else [])) + ["sync=false"], stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
w, h = 320, 240
_head = (shlex.split(os.environ["RMFLASH_CAPHEAD"]) if os.environ.get("RMFLASH_CAPHEAD") else  # напр. rtspsrc … ! avdec_h264
         ["v4l2src", f"device={dev}", "!", f"image/jpeg,width={cw},height={ch},framerate={cf}/1",
          "!", "queue", "max-size-buffers=1", "leaky=downstream", "!"] + shlex.split(dec))
cap = subprocess.Popen(["gst-launch-1.0", "-q"] + _head + ["!", "videoconvert", "!", "videoscale", "!",
    f"video/x-raw,format=GRAY8,width={w},height={h}", "!", "fdsink", "fd=1", "sync=false"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
# область кадру камери (частки x0,y0,x1,y1), дефолт — центральна половина; напр. RMFLASH_ROI=0.6,0.6,0.95,0.95
_r = [float(v) for v in os.environ.get("RMFLASH_ROI", "0.25,0.25,0.75,0.75").split(",")]
rx0, ry0, rx1, ry1 = int(_r[0] * w), int(_r[1] * h), int(_r[2] * w), int(_r[3] * h)
frames, stop, cur = [], False, [BLACK]
lock = threading.Lock()
def reader():
    while not stop:
        b = bytearray()
        while len(b) < w * h:
            c = cap.stdout.read(w * h - len(b))
            if not c: return
            b += c
        t = time.time(); s = n = 0
        for y in range(ry0, ry1, 2):
            row = b[y * w + rx0:y * w + rx1:2]; s += sum(row) / len(row); n += 1
        frames.append((t, s / n))
def keeper():                        # тримати потік кадрів живим (30 Гц), щоб waylandsink не простоював
    while not stop:
        with lock: disp.stdin.write(cur[0]); disp.stdin.flush()
        time.sleep(1 / KEEP_HZ)
threading.Thread(target=reader, daemon=True).start(); threading.Thread(target=keeper, daemon=True).start()
time.sleep(4)
toggles, state = [], 0
for i in range(N):
    state ^= 1
    with lock:
        cur[0] = WHITE if state else BLACK
        t0 = time.time(); disp.stdin.write(cur[0]); disp.stdin.flush()
    toggles.append(t0)
    time.sleep(PER + random.uniform(0, 0.08))
stop = True; time.sleep(0.3); cap.kill(); disp.kill()
lat = []
for tt in toggles:
    base = [v for t, v in frames if tt - 0.15 <= t <= tt]
    fin = [v for t, v in frames if tt + PER - 0.2 <= t <= tt + PER - 0.01]
    if not base or not fin: continue
    b, f = statistics.median(base), statistics.median(fin)
    if abs(f - b) < 20: continue
    for t, v in frames:
        if t > tt and abs(v - b) > 0.5 * abs(f - b): lat.append((t - tt) * 1000); break
if os.environ.get("RMFLASH_RAW"):           # сирі значення для об'єднання блоків (latpool.py)
    with open(os.environ["RMFLASH_RAW"], "a") as fh:
        fh.write("".join("%.1f%s" % (v, os.linesep) for v in lat))
lat.sort(); fr = [t for t, _ in frames]
fps = len([1 for t in fr if fr[0] + 3 <= t <= fr[0] + 13]) / 10.0 if fr else 0
if lat:
    q = lambda k: lat[min(len(lat) - 1, int(k * len(lat)))]
    print(f"{name}: n={len(lat)}/{N} median={statistics.median(lat):.1f} p10={q(0.1):.1f} p90={q(0.9):.1f} min={lat[0]:.1f} max={lat[-1]:.1f} fps_real={fps:.1f}")
else:
    print(f"{name}: no detections, frames={len(frames)}")
