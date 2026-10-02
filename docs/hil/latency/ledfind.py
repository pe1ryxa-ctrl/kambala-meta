# Знайти світлодіод у кадрі камери: блимаємо ним (лише ним) і рахуємо попіксельну різницю «увімкнено − вимкнено».
# python3 ledfind.py <brightness_path> [секунд=12]; env G2G_URL. Друкує найкращу область (частки кадру) для ROI_DW.
import os, subprocess, sys, threading, time
LED = sys.argv[1]; DUR = float(sys.argv[2]) if len(sys.argv) > 2 else 12
URL = os.environ.get("G2G_URL", "rtsp://10.66.0.1:8554/node/sim")
w, h = 640, 480
cap = subprocess.Popen(["gst-launch-1.0", "-q", "rtspsrc", f"location={URL}", "protocols=tcp", "latency=0", "!", "rtph264depay", "!",
    "h264parse", "!", "avdec_h264", "!", "videoconvert", "!", "videoscale", "!", f"video/x-raw,format=GRAY8,width={w},height={h}",
    "!", "fdsink", "fd=1", "sync=false"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
frames, stop = [], False
def reader():
    while not stop:
        b = bytearray()
        while len(b) < w * h:
            c = cap.stdout.read(w * h - len(b))
            if not c: return
            b += c
        frames.append((time.time(), bytes(b)))
threading.Thread(target=reader, daemon=True).start()
time.sleep(5)
tog = []; st = 0; t_end = time.time() + DUR
while time.time() < t_end:
    st ^= 1; t = time.time()
    with open(LED, "w") as fh: fh.write(str(st))
    tog.append((t, st)); time.sleep(0.6)
time.sleep(1); stop = True; cap.kill()
with open(LED, "w") as fh: fh.write("0")
on = [0] * (w * h); off = [0] * (w * h); non = noff = 0
for i, (t, st) in enumerate(tog):
    t1 = tog[i + 1][0] if i + 1 < len(tog) else t + 0.6
    for tf, b in frames:
        if t + 0.40 <= tf <= t1 + 0.15:     # кадри, що прийшли пізно в інтервалі (затримка ланцюга ~0.2 с)
            acc = on if st else off
            for k in range(0, w * h, 1): acc[k] += b[k]
            if st: non += 1
            else: noff += 1
print("frames on/off:", non, noff)
diff = sorted(((on[k] / max(non, 1) - off[k] / max(noff, 1), k) for k in range(w * h)), reverse=True)[:40]
xs = [k % w for _, k in diff]; ys = [k // w for _, k in diff]
print("top:", [(round(d), k % w, k // w) for d, k in diff[:10]])
print("ROI_DW=%.3f,%.3f,%.3f,%.3f" % (min(xs) / w, min(ys) / h, (max(xs) + 1) / w, (max(ys) + 1) / h))
