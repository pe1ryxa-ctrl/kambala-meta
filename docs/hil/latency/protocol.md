# Протокол замірів затримки відео

Журнал лише доповнюється: нові записи — в кінець. Кожен запис містить дату й час (Київ), стенд і умови, скрипт і його коміт, а також сирий вивід. Висновки й зведені таблиці — у `README.md`. Методика — скіл `video-latency`.

## 2026-10-02 (зведено із сесії, до запуску журналу)
- Ділянка 1, RPi 5: framebuffer → ASUS → камера → V399 → jpegdec, `flash.py`, n=40 на варіант:
  - a640_30: 67,1 мс
  - b640_60: 69,8 мс
  - c320_60: 69,4 мс
  - e640_30av: 68,2 мс
  - Реальна частота 25 к/с, повтор із розфазуванням: seg1 — 71,8 мс (45–94).
- Ділянки 1+2, RPi 5 локально через кодер node-sim: 82,5 і 87,1 мс. Через VPS (Wi-Fi): 107 мс, p90 400 (зависання).
- codesrc, ділянка 2 (локально): 4–5 мс. Петля через VPS: 18–23 мс чисті. RPi 5 → VPS → РМ: avdec 21–23, v4l2h264dec 23–26 мс чисті. Зсуви NTP: RPi 5 +9,4, РМ +16,0.
- Показ, РМ-1, V399 на РМ, I420 720×576 (кадр без площин U/V — сирий дефект; пари порівнянні):
  - ASUS: labwc 99,3 / kms 89,9;
  - повтор із ROI: ASUS labwc 103,8 / kms 97,1; Daewoo labwc 112,6 / kms 102,1.

## 2026-10-02 12:41 — матриця показу, labwc 0.9.8 (до оновлення)
Стенд: РМ-1 (RPi 4, trixie, ядро 6.18.39), V399 на РМ `/dev/video0` 640x480@30 MJPG → jpegdec (реально 25 к/с). Камера бачить ASUS (HDMI-A-1) і Daewoo (HDMI-A-2, правий нижній кут кадру). ROI: ASUS 0.15,0.25,0.60,0.60; Daewoo 0.70,0.74,0.96,0.95. Кадр I420 (з площинами U/V), n=40, період 0,8 с + 0–80 мс. Скрипт: `rm_display_matrix.sh v098` (у репо — наступним комітом).
```
v098_labwc_daewoo_720: n=40/40 median=117.8 p10=99.4 p90=145.5 min=71.1 max=168.2 fps_real=25.0
v098_labwc_daewoo_native: n=40/40 median=110.0 p10=90.6 p90=133.9 min=78.0 max=158.7 fps_real=25.0
v098_labwc_asus_720: n=40/40 median=100.6 p10=87.6 p90=122.2 min=68.3 max=130.6 fps_real=25.0
v098_labwc_asus_native: n=40/40 median=139.9 p10=119.8 p90=157.4 min=109.8 max=186.3 fps_real=24.9
v098_kms_daewoo_720: n=40/40 median=97.0 p10=74.6 p90=118.4 min=61.9 max=128.5 fps_real=25.0
v098_kms_daewoo_native: n=40/40 median=100.8 p10=84.7 p90=116.9 min=72.2 max=141.3 fps_real=25.0
v098_kms_asus_720: n=40/40 median=98.8 p10=83.9 p90=122.8 min=68.2 max=139.2 fps_real=24.9
```
Примітка: `asus_native` (1920×1080 I420, ~3 МБ на кадр через трубу Python → videoconvert) — артефакт методу: подача кадру на CPU RPi 4 повільна. Не характеризує екран.

## 2026-10-02 12:49 — оновлення labwc 0.9.8 → 0.20.1 на РМ-1, матриця показу
Оновлення: `apt-get install labwc` → labwc 0.20.1 (wlroots 0.20.2), + `libwlroots-0.20`; нічого не видалено. Сесію перезапущено (`getty@tty1`): розкладка KWS-038 збереглась (HDMI-A-2 на 3920,0), kambala-display / outputs / ui — active. Відкат: `sudo apt-get install labwc=0.9.8-1+rpt1`. Умови — як у попередньому записі. Без kmssink (від labwc не залежить — див. v098_kms_*).
```
v020_labwc_daewoo_720: n=40/40 median=105.2 p10=80.3 p90=132.4 min=68.3 max=162.7 fps_real=25.0
v020_labwc_daewoo_native: n=40/40 median=103.2 p10=92.5 p90=130.2 min=84.2 max=151.2 fps_real=25.0
v020_labwc_asus_720: n=40/40 median=98.3 p10=76.3 p90=129.4 min=69.7 max=133.6 fps_real=25.0
v020_labwc_asus_native: n=40/40 median=133.6 p10=111.7 p90=154.3 min=106.6 max=164.3 fps_real=25.0
```
Те саме з `<core><allowTearing>fullscreenForced</allowTearing></core>` (тимчасово, rc.xml відновлено):
```
v020tear_labwc_daewoo_720: n=40/40 median=113.4 p10=87.1 p90=132.0 min=63.7 max=152.1 fps_real=25.0
v020tear_labwc_daewoo_native: n=40/40 median=116.4 p10=94.4 p90=145.4 min=72.3 max=157.4 fps_real=25.0
v020tear_labwc_asus_720: n=40/40 median=102.1 p10=84.9 p90=118.8 min=65.5 max=167.8 fps_real=25.0
v020tear_labwc_asus_native: n=40/40 median=135.9 p10=114.5 p90=168.9 min=103.7 max=227.2 fps_real=25.0
```
Стан після серії: labwc 0.20.1 лишається на РМ-1, allowTearing вимкнено (rc.xml = копія).

## 2026-10-02 12:55–13:21 — блоковий замір показу на Daewoo (пілот), labwc 0.20.1
Стенд: РМ-1 (RPi 4), labwc 0.20.1, V399 на РМ 640x480@30 → jpegdec (25 к/с), ROI Daewoo 0.70,0.74,0.96,0.95, кадр I420 720×576. Чергування 10 блоків по 50: labwc / labwc+`allowTearing=fullscreenForced` / `kmssink connector-id=44` (labwc зупинено). Скрипт `rm_display_blocks.sh blk2` (BLOCKS=10 PB=50), підсумок `latpool.py` — середнє, 95% ДІ bootstrap. Блок 6 labwc/tear: мало детекцій (10/50, 6/50) і викид 664 мс — ймовірно, збій показу після перезапуску сесії; у підсумку залишено.
```
blk2_labwc_b1: n=50/50 median=111.5 p10=84.8 p90=144.4 min=73.7 max=156.0 fps_real=25.0
blk2_tear_b1: n=50/50 median=118.6 p10=82.1 p90=131.9 min=55.6 max=139.6 fps_real=25.0
blk2_kms_b1: n=50/50 median=101.4 p10=85.2 p90=122.9 min=68.6 max=136.5 fps_real=25.0
blk2_labwc_b2: n=50/50 median=113.6 p10=88.5 p90=133.9 min=68.2 max=144.1 fps_real=25.0
blk2_tear_b2: n=50/50 median=112.2 p10=89.8 p90=129.1 min=75.6 max=168.1 fps_real=25.0
blk2_kms_b2: n=50/50 median=101.8 p10=81.6 p90=120.2 min=65.1 max=131.3 fps_real=25.0
blk2_labwc_b3: n=50/50 median=117.0 p10=92.8 p90=133.4 min=66.2 max=178.0 fps_real=25.0
blk2_tear_b3: n=50/50 median=110.0 p10=82.0 p90=134.0 min=69.2 max=151.4 fps_real=25.0
blk2_kms_b3: n=50/50 median=97.1 p10=84.8 p90=116.1 min=68.6 max=136.6 fps_real=25.0
blk2_labwc_b4: n=50/50 median=110.3 p10=87.2 p90=142.0 min=66.9 max=183.1 fps_real=24.8
blk2_tear_b4: n=50/50 median=114.6 p10=89.7 p90=139.1 min=66.9 max=161.2 fps_real=25.0
blk2_kms_b4: n=50/50 median=98.5 p10=82.8 p90=118.3 min=65.9 max=130.4 fps_real=25.0
blk2_labwc_b5: n=50/50 median=106.6 p10=87.2 p90=135.7 min=76.8 max=140.0 fps_real=25.0
blk2_tear_b5: n=50/50 median=108.7 p10=81.7 p90=135.0 min=70.0 max=141.6 fps_real=25.0
blk2_kms_b5: n=50/50 median=104.6 p10=84.1 p90=121.0 min=63.7 max=130.0 fps_real=25.0
blk2_labwc_b6: n=10/50 median=113.7 p10=97.8 p90=664.4 min=92.6 max=664.4 fps_real=25.0
blk2_tear_b6: n=6/50 median=128.5 p10=93.2 p90=141.4 min=93.2 max=141.4 fps_real=25.0
blk2_kms_b6: n=50/50 median=100.6 p10=81.2 p90=116.0 min=70.0 max=139.9 fps_real=25.0
blk2_labwc_b7: n=50/50 median=115.4 p10=95.3 p90=133.1 min=66.4 max=165.4 fps_real=25.0
blk2_tear_b7: n=50/50 median=111.8 p10=99.3 p90=143.6 min=87.9 max=148.9 fps_real=25.0
blk2_kms_b7: n=50/50 median=100.9 p10=76.1 p90=128.8 min=63.0 max=150.9 fps_real=25.0
blk2_labwc_b8: n=50/50 median=111.4 p10=92.7 p90=131.8 min=75.5 max=154.0 fps_real=24.9
blk2_tear_b8: n=50/50 median=112.2 p10=83.8 p90=134.9 min=72.6 max=158.2 fps_real=25.0
blk2_kms_b8: n=50/50 median=101.6 p10=74.1 p90=121.4 min=66.8 max=136.5 fps_real=25.0
blk2_labwc_b9: n=50/50 median=106.3 p10=85.5 p90=131.6 min=76.1 max=165.5 fps_real=24.9
blk2_tear_b9: n=50/50 median=106.1 p10=89.1 p90=136.3 min=78.0 max=152.8 fps_real=25.0
blk2_kms_b9: n=50/50 median=97.3 p10=85.0 p90=125.1 min=72.0 max=132.5 fps_real=25.0
blk2_labwc_b10: n=50/50 median=107.3 p10=84.0 p90=134.2 min=77.1 max=144.5 fps_real=25.0
blk2_tear_b10: n=50/50 median=105.6 p10=88.4 p90=132.5 min=72.4 max=151.6 fps_real=25.0
blk2_kms_b10: n=50/50 median=103.7 p10=82.5 p90=128.5 min=72.9 max=133.9 fps_real=24.9
rc.xml = копія
blk2_labwc.raw: n=460 mean=113.7 [110.8..117.4] median=111.5 sd=37.1
blk2_tear.raw: n=456 mean=111.2 [109.5..112.8] median=111.9 sd=18.5  vs blk2_labwc.raw: -2.6 [-6.6..+1.0]
blk2_kms.raw: n=500 mean=101.1 [99.7..102.5] median=100.5 sd=15.8  vs blk2_labwc.raw: -12.7 [-16.7..-9.3]
30387 labwc
active
active
DONE

```
Стан після серії: rc.xml = копія, labwc 0.20.1 запущено, kambala-display / kambala-outputs — active.

## 2026-10-02 14:14–14:18 — від скла до скла, усе на РМ-1 (RPi 4), серія g2g1
Схема: РМ-1 блимає на ASUS (I420 720×576, waylandsink, тимчасове правило labwc → HDMI-A-1) → аналогова камера → V399 на РМ-1 → `camserve.py`: v4l2src MJPG 640x480@30 → v4l2jpegdec → videoconvert I420 → **v4l2h264enc** (2 Мбіт/с, GOP 75, baseline, repeat_sequence_header) → RTSP :8554 → VPS MediaMTX `node/sim` (джерело тимчасово `rtsp://10.66.0.3:8554/video0`, `vps_g2g_source.sh rm1`, перезапуск mediamtx) → РМ-1 Flight Display (вузол sim) → Daewoo. Аналіз: `g2g.py` (потік node/sim з VPS на РМ, ROI ASUS 0.15,0.25,0.60,0.60 / Daewoo 0.70,0.74,0.96,0.95; затримка = різниця індексів кадрів камери × 40 мс). Аплінк РМ-1 — Ethernet.
```
g2g1: n=198/200 mean=340.0 median=360.0 p10=280.0 p90=400.0 sd=79.0 | arrival_diff_mean=339.9 fps_stream=25.0
```
Стан після: rc.xml відновлено, kambala-display active, camserve працює, node/sim → РМ-1.

## 2026-10-02 14:20–14:50 — розклад «від скла до скла» на РМ-1 (camserve на РМ-1, node/sim → РМ-1)
**Матриця g2g:** кодер і декодер JPEG у `camserve`; декодер Flight Display. N=100. Детектор до виправлення — див. примітку.
```
g2gm_hwjpeg_hwenc: n=100/100 mean=352.4 median=360.0 p10=320.0 p90=400.0 sd=55.9
g2gm_swjpeg_hwenc: n=100/100 mean=280.8 median=340.0 p10=120.0 p90=400.0 sd=119.1
g2gm_swjpeg_x264 / hwjpeg_x264: no detections (x264enc не було на РМ-1; поставлено gstreamer1.0-plugins-ugly)
g2gd_swdisp_hwjpeg_hwenc (Flight Display avdec_h264): n=100/100 mean=366.0 median=360.0 p10=320.0 p90=440.0 sd=63.8
g2gd_swdisp_swjpeg_x264 (avdec_h264 + jpegdec + x264): n=100/100 mean=279.2 median=300.0 p10=120.0 p90=400.0 sd=122.6
```
Примітка. Варіанти з великим sd і p10=120 двомодальні. Причина — АРП аналогової камери: коли спалахує ASUS, камера знижує підсилення, і яскравість Daewoo в кадрі одразу змінюється у протилежний бік. Детектор брав |зміну|. Виправлено в `g2g.py`: зараз рахується лише перетин у напрямку кінцевого рівня.

**Спалах ASUS (labwc) → камера → … → аналіз на РМ-1, один годинник, `rm_seg_camserve.sh seg1`, N=60:**
```
seg1_camserve_local (V399→v4l2jpegdec→v4l2h264enc→RTSP 127.0.0.1→avdec): median=151.8 p10=137.7 p90=172.4
seg1_via_vps_tcp (… → VPS MediaMTX → РМ, TCP): median=177.4 p10=148.7 p90=199.2
seg1_via_vps_udp (… UDP, drop-on-latency): median=166.0 p10=143.6 p90=190.6
```
Довідково: напряму V399→jpegdec (без кодера), ASUS через labwc — ≈ 98–104 мс (v098/v020 asus_720).

**g2g з виправленим детектором, N=100:**
```
g2gp1 (мінімальний плеєр gst-launch UDP latency=0 v4l2h264dec waylandsink замість Flight Display): mean=333.6 median=320.0 p10=280.0 p90=400.0 sd=56.3
g2g2_fd (Flight Display, штатно): mean=324.8 median=320.0 p10=280.0 p90=360.0 sd=56.1
```
Flight Display проти мінімального плеєра — різниці немає. Стан після серій: rc.xml і .env відновлено, kambala-display active, camserve (v4l2jpegdec + v4l2h264enc) працює, node/sim → РМ-1.

## 2026-10-02 14:55–15:00 — g2g: діагностика АРП і метод «половинки»
Покадровий розбір серії `g2gdump` (суцільний спалах): ASUS у кадрі перемикається одразу, а через ~6 кадрів (~240 мс) АРП камери знижує підсилення. Daewoo в кадрі змінюється саме тоді й у той самий бік. Детектор ловив АРП, а не появу картинки на Daewoo, тож **325–366 мс — артефакт методу**.
Виправлення: шаблон `G2G_PATTERN=halves` — ліва половина біла, права чорна, і навпаки; середня яскравість стала. ROI ставили зі знімка потоку (`G2G_SNAP`): ASUS 0.18,0.25,0.45,0.60 (усередині лівої половини), Daewoo 0.74,0.78,0.83,0.90 (там, де Daewoo показує ліву половину ASUS).
```
g2gh1: n=100/100 mean=154.8 median=160.0 p10=120.0 p90=160.0 sd=14.6 | arrival_diff_mean=154.7 fps_stream=25.0
```
Покадрово: Daewoo перемикається одним стрибком через 4 кадри після ASUS (184 → 236), без супутніх змін яскравості.

## 2026-10-02 15:01–15:12 — g2g «половинки», повторні серії (РМ-1 сам собі вузол: camserve v4l2jpegdec + v4l2h264enc; node/sim → РМ-1; Flight Display на Daewoo)
```
g2gh2: n=199/200 mean=158.4 median=160.0 p10=160.0 p90=160.0 sd=9.7 | arrival_diff_mean=157.6 fps_stream=24.8
g2gh3: n=198/200 mean=160.2 median=160.0 p10=120.0 p90=200.0 sd=20.3 | arrival_diff_mean=160.1 fps_stream=24.9
latpool: g2gh1 154.8 [152.0..157.6]; g2gh2 158.4 [157.0..159.6]; g2gh3 160.2 [157.4..163.0]
```
**Від скла до скла ≈ 158 мс** (497 замірів, три серії, розкид між серіями ≤ 5 мс).

## 2026-10-02 15:15–15:25 — затримка дисплея проти світлодіода Caps Lock (метод Gans: еталон без додаткового обладнання)
Клавіатура Logitech K300 (USB, РМ-1) у кадрі поруч з ASUS. Світлодіод `/sys/class/leds/input6::capslock/brightness` (тимчасово chmod 666). Знайдено `ledfind.py` (блимання лише світлодіодом, різниця ~100): ROI 0.347,0.771,0.359,0.790. Спалах і світлодіод вмикаються в той самий момент. Затримка = кадр зміни екрана − кадр зміни світлодіода, обидва в тих самих кадрах камери. Аналіз 640×480.
```
led_asus1 (ASUS через labwc, моя подача кадру Python → gst → waylandsink): n=199/200 mean=44.8 median=40.0 p10=40.0 p90=80.0 sd=16.3 | arrival_diff_mean=46.0
led_dw1 (Daewoo): n=33/200 mean=41.2 — НЕДІЙСНО: ROI спалаху на Daewoo поставлено навмання; перемірити зі знімком
```
**Дисплей ASUS (композитор + подача + панель) ≈ 45 мс** [≈ ±2,3]. Світлодіод вважаємо миттєвим (USB HID, кілька мс), тож оцінка може бути заниженою на ці кілька мс.
