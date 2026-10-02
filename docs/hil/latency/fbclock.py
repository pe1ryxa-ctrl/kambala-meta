import datetime, time, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont
W, H, STRIDE = 1920, 1080, 3840
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf", 300)
l1, l2 = font.getbbox("00:00"), font.getbbox("000")
bw = min(max(l1[2], l2[2]) + 40, W); lh = max(l1[3], l2[3]) + 20; bh = 2 * lh + 20
x0 = (W - bw) // 2; y0 = (H - bh) // 2
fb = os.open("/dev/fb0", os.O_RDWR)
os.pwrite(fb, bytes(STRIDE * H), 0)
img = Image.new("L", (bw, bh)); d = ImageDraw.Draw(img)
off1 = (bw - l1[2]) // 2; off2 = (bw - l2[2]) // 2
cnt, t0, worst = 0, time.time(), 0.0
while True:
    ts = time.time()
    n = datetime.datetime.now(datetime.timezone.utc)
    d.rectangle((0, 0, bw, bh), fill=0)
    d.text((off1, 0), n.strftime("%M:%S"), font=font, fill=255)
    d.text((off2, lh + 20), "%03d" % (n.microsecond // 1000), font=font, fill=255)
    a = np.asarray(img, dtype=np.uint16)
    buf = (((a >> 3) << 11) | ((a >> 2) << 5) | (a >> 3)).astype("<u2").tobytes()
    for r in range(bh):
        os.pwrite(fb, buf[r * bw * 2:(r + 1) * bw * 2], (y0 + r) * STRIDE + x0 * 2)
    dt = time.time() - ts
    worst = max(worst, dt)
    cnt += 1
    if time.time() - t0 >= 5:
        print('fps %.1f  draw_ms avg %.1f worst %.1f' % (cnt/(time.time()-t0), 1000*(time.time()-t0)/cnt, 1000*worst), flush=True)
        cnt, t0, worst = 0, time.time(), 0.0
    time.sleep(0.002)
