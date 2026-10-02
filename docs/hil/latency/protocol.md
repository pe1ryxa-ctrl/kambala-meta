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
