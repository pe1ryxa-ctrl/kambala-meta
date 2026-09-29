# Захоплювачі CVBS/PAL із сирим кадром і (бажано) напівкадром — дослідження для Kambala

Дата: 2026-09-29. Метод перевірки коду: сирці `torvalds/linux` master (raw.githubusercontent.com) і defconfig `raspberrypi/linux` гілок `rpi-6.12.y` та `rpi-6.18.y` (типова гілка репозиторію на сьогодні — `rpi-6.18.y`).

> Обмеження дослідження: з цього середовища не відкривалися waveshare.com, spotpear, linuxtv.org, forums.raspberrypi.com, prom.ua, rozetka, AliExpress. Тому дані про магазини, ціни й Waveshare взято з пошукових сніпетів (посилання наведено, але сторінки я сам не відкривав). Такі місця позначено **[сніпет]**. Висновки про драйвери зроблено з вихідного коду, який я прочитав сам (**[код]**).

---

## 1. Резюме й рекомендація

**Жоден mainline-драйвер CVBS-грабера не віддає напівкадр (`V4L2_FIELD_ALTERNATE`) «з коробки».** Усі USB-драйвери (usbtv, stk1160, em28xx, cx231xx) віддають склеєний кадр 720x576 `V4L2_FIELD_INTERLACED` із частотою 25/с. Виняток — tw68 (старий PCI, не PCIe): він дає `TOP`/`BOTTOM`/`SEQ_TB`, але не `ALTERNATE`. Проте всі ці драйвери **не буферизують на рівні чипа**, на відміну від MS2107. Буфер повертається в userspace одразу після останнього рядка другого поля (плюс ≤1–8 мс на ізохронний URB), тому очікувана затримка «чип + USB + драйвер» ≈ 40–50 мс проти 205–232 мс у MS2107. Щоб отримати поле за ≈20 мс, потрібен невеликий патч драйвера (завершувати буфер після кожного поля, 720x288, `ALTERNATE`). Найпростіше це зробити в usbtv, бо там апаратні заголовки чанків уже містять ознаку поля.

**Рекомендація — купити 2 пристрої й заміряти тим самим методом («годинник RPi 5 у кадрі»):**

1. **Fushicai UTV007 (`1b71:3002`, драйвер `usbtv`) — основний кандидат.** Віддає YUYV 720x576 без масштабування. Буфер завершується в тій самій обробці URB, де прийшов останній чанк другого поля, а URB короткий: 8 пакетів ≈ 1 мс. Патч на `ALTERNATE` тут найпростіший (~30 рядків). Модуль `CONFIG_VIDEO_USBTV=m` є в RPi OS. Ризик: чип знято з виробництва, під назвою «UTV007» часто продають MS2106 (`534d:0021`, UVC), тому купувати треба з поверненням і перевіряти `lsusb`. У Україні ≈ 210–470 грн **[сніпет]**.
2. **EasyCAP DC60 на Syntek STK1160 + SAA7113/GM7113 (`05e1:0408`, `stk1160`)** або **EM2860 + SAA7113 (`eb1a:2860/2861`, `em28xx`)** — запасний варіант. Обидва драйвери є в RPi OS. Декодер SAA7113 добре працює з «брудним» сигналом. Кадр завершується на маркері початку наступного кадру, додатково ≤8 мс на URB (64 пакети). У em28xx більший вибір роздільностей (апаратний масштабувальник). STK1160 DC60 є на prom.ua за 304–464 грн **[сніпет]**, EM2860 як окремий модуль є на AliExpress **[сніпет]**.

PCIe TW6869 на CM4-DUAL-ETH-BOX-A **не рекомендую**. Єдина лінія PCIe CM4 на цій платі, найімовірніше, вже зайнята (ETH1 = RTL8111H через PCIe, три порти USB 3.2 — через VL805 за PCIe-комутатором). Вільного слота немає. `CONFIG_VIDEO_TW686X` вимкнено в RPi defconfig. Є відомий баг DMA-алокації TW6869 на CM4. Сам чип EOL.

Що саме заміряти: (а) стоковий драйвер, `v4l2-ctl --stream-mmap --stream-count` + годинник у кадрі, порівняти з V399/MS2107; (б) після патча `ALTERNATE` — те саме на 50 полях/с.

---

## 2. Таблиця кандидатів

| Чип (міст + декодер) | VID:PID | Сирі формати / роздільності | `field` у драйвері | Драйвер / mainline / RPi OS | Затримка (оцінка з коду; заміру немає) | Де купити, ціна | Ризики |
|---|---|---|---|---|---|---|---|
| **Fushicai UTV007** (декодер вбудований) | `1b71:3002` (також `1f71:3301`, `1f71:3306`) | YUYV, лише 720x576 (PAL) / 720x480 (NTSC), без масштабувальника | `INTERLACED`, 25 кадрів/с | `usbtv`, mainline з ~3.11 (2013); `CONFIG_VIDEO_USBTV=m` у bcm2711/bcm2712 defconfig | буфер завершується одразу після останнього чанка 2-го поля; URB = 8 пакетів (~1 мс), 16 URB у черзі → ≈40–45 мс від початку кадру | prom.ua 325–374 грн, Епіцентр, kidstaff 210 грн **[сніпет]**; AliExpress «EasyCAP UTV007» **[сніпет]** | знятий з виробництва; підміна на MS2106 (`534d:0021`); розмітка непарне/парне (odd/even) іноді «стрибає» |
| **Syntek STK1160 + SAA7113/GM7113C** (EasyCAP DC60) | `05e1:0408` | UYVY 720x576, масштабування через децимацію (n/(n+1)) | `INTERLACED` | `stk1160`, mainline з ~3.7; `CONFIG_VIDEO_STK1160=m` | буфер завершується на маркері `0xc0` (початок наступного кадру); URB = 64 пакети (8 мс), 16 URB → ≈42–50 мс | prom.ua 304 / 464 грн «STK1160 DC-60» **[сніпет]**; uawest.com **[сніпет]** | під назвою «DC60» трапляються UTV007/MS2106/EM2860 |
| **Empia EM2860/2861/2863 + SAA7113/GM7113** | `eb1a:2860`, `eb1a:2861`, `eb1a:2863`, клони `1b80:e309` та ін. | YUYV (також RGB565, Bayer, YUV411P) 720x576 і менші (апаратний масштабувальник) | `INTERLACED`; режим «лише верхнє поле» у коді є, але позначений FIXME як непрацездатний | `em28xx`, mainline з 2.6.x; `CONFIG_VIDEO_EM28XX(_V4L2)=m` | буфер завершується на заголовку наступного верхнього поля; URB = 64 пакети (8 мс), 5 URB → ≈42–50 мс | AliExpress «USB video capture card 1-channel EM2860» (модуль) **[сніпет]**; в Україні з явним «EM2860» не знайдено | `eb1a:2861` може визначитися як «Unknown board» → потрібен `card=`; багато «EM2860» насправді інші чипи |
| **Conexant CX23102** (cx231xx; Hauppauge USB-Live2 тощо) | `2040:c200` та ін. | YUYV 720x576 | `INTERLACED` | `cx231xx`, `CONFIG_VIDEO_CX231XX=m` | не аналізував детально | переважно вживані; ціна вища | рідкісний, дорожчий |
| **Somagic SMI2021** | `1c88:0007` (без прошивки), `1c88:003c` | UYVY 720x576 (позадеревний драйвер) | — | **НЕ в mainline**: RFC v3 2013 не злито, потрібен бінарний blob прошивки | — | трапляється під назвою «EasyCAP» | потрібні позадеревний модуль і прошивка; не радимо |
| **Techwell/Intersil TW6869/6864** (PCIe) | PCI `1797:6869` / `6864` | UYVY/YUYV/RGB565 720x576 | `INTERLACED` (memcpy/contig) або `SEQ_TB` (sg); кадр, не поле | `tw686x`, mainline з ~4.7; **вимкнено** в RPi defconfig | IRQ на кадр; окреме поле не отримати | PCIe x1, 4 канали; на AliExpress важко знайти, чип EOL | немає вільного PCIe у BOX-A; баг DMA на CM4 (issue #4197) |
| **Techwell TW6800/6801/6804** (tw68) | PCI `1797:6800…` | YUYV/UYVY/RGB 720x576 | `TOP`/`BOTTOM`/`SEQ_TB`/`INTERLACED` | `tw68`; вимкнено в RPi | лише одне поле (25/с) або пара полів | старий PCI (не PCIe) | для CM4 непридатний |
| (для порівняння) MS2107 | `0002:afa1` / `345f:*` | YUYV 720x576 (UVC) | UVC, `NONE` | uvcvideo | виміряно 205–232 мс (буферизація 2–3 кадрів) | — | — |
| MS2106 «нова EasyCAP» | `534d:0021` | YUYV/MJPG, заявлено 720x576, але в деяких партіях максимум 640x480 | UVC | uvcvideo | не вимірювалася, імовірно як MS2107 | продається під назвою «UTV007» | не брати |

---

## 3. Кандидати докладно

### 3.1 Fushicai UTV007 — `usbtv`

- **Формати [код]:** `usbtv-video.c`: єдиний формат `V4L2_PIX_FMT_YUYV` (рядки 643, 654). Норми PAL → `cap_width=720, cap_height=576`, NTSC → 720x480 (рядки 53–59). Масштабувальника немає.
  https://github.com/torvalds/linux/blob/master/drivers/media/usb/usbtv/usbtv-video.c
- **Поля [код]:** `f->fmt.pix.field = V4L2_FIELD_INTERLACED` (рядок 655). У `usbtv_image_chunk()` кожен 256-байтовий чанк має заголовок із `frame_id`, прапорцем `odd` (поле) і `chunk_no` (`usbtv.h`: `USBTV_ODD`, `USBTV_CHUNK_NO`). Рядки пишуться через рядок (`usbtv_chunk_to_vbuf`, `line*2 + !odd`). Буфер віддається через `vb2_buffer_done`, коли прийшов **останній чанк поля** (`chunk_no == n_chunks-1`) і це перехід на непарне поле (`odd && !last_odd`), тобто одразу після завершення другого поля. Буферизації на рівні кадру немає.
  https://github.com/torvalds/linux/blob/master/drivers/media/usb/usbtv/usbtv.h
- **Напівкадр:** `ALTERNATE` у стоковому драйвері немає. **Патч тривіальний:** `n_chunks` рахувати для 720x288, писати без чергування рядків (`line` замість `line*2+!odd`) і викликати `vb2_buffer_done` на кожному `chunk_no == n_chunks-1` з `buf->vb.field = odd ? V4L2_FIELD_TOP : V4L2_FIELD_BOTTOM` (полярність треба перевірити). У `g/try/s_fmt` виставити `ALTERNATE`, 720x288. Модуль збирається поза деревом з `raspberrypi-kernel-headers`.
- **USB/URB [код]:** `USBTV_ISOC_TRANSFERS 16`, `USBTV_ISOC_PACKETS 8` (`usbtv.h`). На high-speed це 8 мікрокадрів по 125 мкс ≈ 1 мс на URB, тож внесок драйвера в затримку ≈1 мс. Альтернативне налаштування 1 (`usb_set_interface(..., 0, 1)`).
- **Mainline / RPi:** є в `drivers/media/usb/usbtv` (LKDDb: https://cateee.net/lkddb/web-lkddb/VIDEO_USBTV.html). `CONFIG_VIDEO_USBTV=m` є і в `bcm2711_defconfig`, і в `bcm2712_defconfig` (`rpi-6.12.y`, `rpi-6.18.y`) [код]:
  https://github.com/raspberrypi/linux/blob/rpi-6.18.y/arch/arm64/configs/bcm2711_defconfig
  https://github.com/raspberrypi/linux/blob/rpi-6.18.y/arch/arm64/configs/bcm2712_defconfig
- **VID:PID [код]:** `usbtv-core.c`: `1b71:3002`, `1f71:3301`, `1f71:3306`.
  https://github.com/torvalds/linux/blob/master/drivers/media/usb/usbtv/usbtv-core.c
- **Практика:** BATC (Portsdown, RPi 4) рекомендує саме Fushicai USBTV007, «без драйверів, просто підключити», і попереджає, що під цією назвою продають щонайменше 3 різні чипи **[сніпет]**: https://wiki.batc.org.uk/Fushicai_USBTV007 , https://wiki.batc.org.uk/Portsdown_hardware
  Повідомлення про підміну на Macrosilicon MS2106 (`534d:0021`, «AV TO USB2.0», MBA22N) і про те, що UTV007 вже не виробляється, за словами китайських продавців **[сніпет]**: https://forum.videohelp.com/threads/391378-Trying-to-get-a-cheap-EasyCap-clone-to-work-better , https://www.spinics.net/lists/linux-media/msg224486.html
- **Затримка:** опублікованих цифр у мс не знайшов. У старому форумі є лише «затримка менша за секунду» (http://forums.trossenrobotics.com/archive/index.php/t-6303.html) — для нас неінформативно. З коду: ≈40 мс (два поля) + ≈1–2 мс (URB/xHCI), після патча — ≈20 + 1–2 мс.
- **Купити [сніпет]:** https://prom.ua/p1239303729-usb-karta-videozahvata.html (325 грн, «ТЕХНОБАНК», Львів), https://prom.ua/ua/p1219765138-usb-karta-videozahvata.html (374 грн), https://epicentrk.ua/ua/shop/mplc-karta-videozakhvatu-usb-easycap-utv007-880-1ebe3bb3-50a5-6cc8-949b-5f2f390b8970.html , https://www.kidstaff.com.ua/tema-20858384.html (210 грн), каталог https://prom.ua/Utv-007.html . AliExpress: https://www.aliexpress.com/w/wholesale-usb-easycap-utv007.html . Лот «Chipset 008 replace UTV 007» (https://www.aliexpress.com/item/33002586417.html) — **це вже не UTV007**, не брати.
- **Як розпізнати:** `lsusb` → `1b71:3002 Fushicai USBTV007 Video Grabber [EasyCAP]`. На платі одна мікросхема з маркуванням «UTV007» (QFN), окремого декодера немає. Просити в продавця фото плати або VID:PID.

### 3.2 Syntek STK1160 (+ SAA7113 / GM7113C) — `stk1160`

- **Формати [код]:** лише `V4L2_PIX_FMT_UYVY` (`stk1160-v4l.c:49`). Базова роздільність 720x576 (PAL), менші — децимацією стовпців і рядків (рядки 377–452).
  https://github.com/torvalds/linux/blob/master/drivers/media/usb/stk1160/stk1160-v4l.c
- **Поля [код]:** `field = V4L2_FIELD_INTERLACED` скрізь (`stk1160-v4l.c:359,452`; `stk1160-video.c:93`). У `stk1160_isoc_irq`/обробці пакетів маркер `0xc0` означає початок нового кадру (верхнє поле). Саме тоді викликається `stk1160_buffer_done` для попереднього буфера, а `0x80` — початок другого поля (біт `0x40` = парність). Отже, кадр віддається, коли прийшов маркер наступного кадру (≈ кінець кадрового гасіння після 2-го поля).
  https://github.com/torvalds/linux/blob/master/drivers/media/usb/stk1160/stk1160-video.c
- **Напівкадр:** можливий патчем (завершувати буфер і на `0x80`, і на `0xc0`), але складніший за usbtv: 64-пакетні URB дають ≤8 мс «зернистості».
- **URB [код]:** `STK1160_NUM_PACKETS 64`, `STK1160_NUM_BUFS 16` (`stk1160.h`) → 8 мс на URB.
  https://github.com/torvalds/linux/blob/master/drivers/media/usb/stk1160/stk1160.h
- **VID:PID [код]:** `05e1:0408` (`stk1160-core.c:41`).
- **RPi:** `CONFIG_VIDEO_STK1160=m` [код, defconfig вище]. Історично на RPi 1/2 (dwc_otg) були проблеми з ізохронним потоком (https://github.com/raspberrypi/linux/issues/620 **[сніпет]**). На CM4 через xHCI (VL805) це неактуально, через dwc2 — ризик.
- **Купити [сніпет]:** https://prom.ua/ua/p1300936461-karta-videozahvata-easycap.html (464 грн, «STK1160 EasyCap DC-60»), https://prom.ua/ua/p718646134-karta-easycap-chipset.html (304 грн, «чіпсет STK1160»), https://uawest.com/ua/easycap_dc60.html .
- **Розпізнати:** `lsusb` → `05e1:0408 Syntek ... STK1160`; на платі дві мікросхеми: STK1160 (QFP) + SAA7113H або GM7113C (QFP-44), кварц 24.576 МГц.

### 3.3 Empia EM2860/2861/2863 (+ SAA7113) — `em28xx`

- **Формати [код]:** YUYV (типовий), RGB565, SRGGB8/SBGGR8/SGRBG8/SGBRG8, YUV411P (`em28xx-video.c:95–119`). Роздільність від 48x32 до 720x576 через апаратний масштабувальник (`size_to_scale`/`v4l_bound_align_image`, рядки 1617–1668).
  https://github.com/torvalds/linux/blob/master/drivers/media/usb/em28xx/em28xx-video.c
- **Поля [код]:** `finish_buffer()` ставить `V4L2_FIELD_INTERLACED` (рядки 546–553). `try_fmt` повертає `interlaced_fieldmode ? INTERLACED : TOP`, але в `em28xx.h:594–595` є коментар: `interlaced_fieldmode ... /* FIXME: everything else than interlaced_fieldmode=1 doesn't work */`, а `EM28XX_INTERLACED_DEFAULT 1`. `finish_field_prepare_next()` завершує буфер, коли почалося нове **верхнє** поле (`if (progressive || top_field) finish_buffer`), тобто кадр віддається на заголовку наступного кадру. Поле визначається з `data_pkt[2] & 1`.
  https://github.com/torvalds/linux/blob/master/drivers/media/usb/em28xx/em28xx.h
- **Напівкадр:** патчем (завершувати буфер у `finish_field_prepare_next` на кожному полі, не чергувати рядки в `em28xx_copy_video`). Логіка полів у драйвері вже є.
- **URB [код]:** `EM28XX_NUM_BUFS 5`, `EM28XX_NUM_ISOC_PACKETS 64` → 8 мс на URB. Для bulk-пристроїв (em2874 та ін.) `packet_multiplier 384`.
- **VID:PID [код]:** `em28xx-cards.c`: `eb1a:2860`, `eb1a:2861`, `eb1a:2862`, `eb1a:2863`, `eb1a:2868`, клони `1b80:e309` (Sveon STV40 → `EM2860_BOARD_EASYCAP`), `1b80:e302`, `1b80:e304` тощо. Для `eb1a:2861` плата часто «generic» → може знадобитися `modprobe em28xx card=64` (`EM2860_BOARD_SAA711X_REFERENCE_DESIGN`; номер перевірити за `em28xx-cards.c` / `Documentation/admin-guide/media/em28xx-cardlist.rst`).
  https://github.com/torvalds/linux/blob/master/drivers/media/usb/em28xx/em28xx-cards.c
- **RPi:** `CONFIG_VIDEO_EM28XX=m`, `_V4L2=m`, `_ALSA=m` [код].
- **Купити [сніпет]:** модуль «USB video capture card, 1-channel EM2860» https://www.aliexpress.com/i/1005008710919739.html ; «1 road EM2860 acquisition card + SDK» https://www.aliexpress.com/item/32709048550.html ; оптові DC60 «STK1160/EM2860» https://www.alibaba.com/product-detail/EasyCAP-USB2-0-Video-Capture-DC60-60745857615.html (чип не гарантований). На prom/rozetka явного «EM2860» не знайшов.
- **Розпізнати:** `lsusb` → `eb1a:2860/2861 eMPIA Technology`; на платі EM2860 (LQFP-64) + SAA7113H/GM7113C.

### 3.4 Somagic SMI2021 — поза деревом

- Не в mainline. RFC v3 «Add a driver for the Somagic smi2021 chip» (2013) не злито: https://lwn.net/Articles/565444/ , https://lkml.iu.edu/hypermail/linux/kernel/1310.0/01731.html **[сніпет]**. Позадеревні форки: https://github.com/jonjonarnearne/smi2021 , https://github.com/Manouchehri/smi2021 , https://github.com/DolceTriade/smi2021 . Потрібен бінарний blob прошивки, а `1c88:0007` — це стан до завантаження прошивки **[сніпет]**.
- VID:PID `1c88:0007` / `1c88:003c` — за LinuxTV wiki (копія: https://www.scribd.com/document/434874834/Easycap-LinuxTVWiki) **[сніпет]**.
- **Висновок:** не розглядати.

### 3.5 Conexant cx231xx

- YUYV, `V4L2_FIELD_INTERLACED` (`cx231xx-video.c:83,171,840,883`) [код]; ID `2040:c200` (Hauppauge USB-Live2) та інші (`cx231xx-cards.c`). `CONFIG_VIDEO_CX231XX=m` у RPi [код]. Затримку не аналізував. Пристрої рідкісні й дорожчі, тож лише як резерв.
  https://github.com/torvalds/linux/blob/master/drivers/media/usb/cx231xx/cx231xx-video.c

### 3.6 Techwell/Intersil TW686x (TW6864/6865/6868/6869, PCIe) — `tw686x`

- **Формати [код]:** UYVY, RGB565, YUYV; 720x576 PAL (`TW686X_VIDEO_HEIGHT`), ширину можна зменшити вдвічі.
  https://github.com/torvalds/linux/blob/master/drivers/media/pci/tw686x/tw686x-video.c
- **Поля [код]:** режими DMA `memcpy` (типовий) і `contig` → `TW686X_FRAME_MODE`, `.field = V4L2_FIELD_INTERLACED`; `sg` → `V4L2_FIELD_SEQ_TB`. В усіх режимах одиниця — **кадр**, `ALTERNATE` немає. Переривання DMA агрегуються (`dma_interval`). У коментарі `tw686x-core.c` сказано, що перепрограмування DMA під час потоку «може повністю заморозити машину».
  https://github.com/torvalds/linux/blob/master/drivers/media/pci/tw686x/tw686x-core.c
- **PCI ID [код]:** Techwell `0x6864`, `0x6865`, `0x6868`, `0x6869`.
- **RPi:** `CONFIG_VIDEO_TW686X` **немає** ні в `bcm2711_defconfig`, ні в `bcm2712_defconfig` (`rpi-6.12.y`, `rpi-6.18.y`), хоча `CONFIG_MEDIA_PCI_SUPPORT=y` [код] → потрібна власна збірка модуля.
- **На CM4:** issue «TW6869 PCIe capture card DMA allocation trouble»: `dma_alloc_coherent of size 692224 failed`, `coherent_pool=32M` і збільшення CMA не допомогли **[сніпет]** https://github.com/raspberrypi/linux/issues/4197 (Jetson TX2 має таку саму проблему: https://forums.developer.nvidia.com/t/tw6869-driver-fails-with-12-cannot-allocate-memory-on-jetson-tx2-nx-pcie-dma-allocation-issue/372007).
- **Статус чипа:** Renesas — «not recommended for new designs» **[сніпет]** https://www.renesas.com/en/products/tw6869
- LKDDb: https://cateee.net/lkddb/web-lkddb/VIDEO_TW686X.html

### 3.7 tw68 (TW6800/6801/6804/6816, PCI)

- [код] `tw68-video.c`: `try_fmt` допускає `TOP`, `BOTTOM`, `INTERLACED`, `SEQ_BT`, `SEQ_TB`; якщо висота ≤ maxh/2, типово `BOTTOM` (одне поле, 25/с). `ALTERNATE` немає. Шина — PCI (не PCIe), тож для CM4 непридатний. У RPi defconfig модуля немає.
  https://github.com/torvalds/linux/blob/master/drivers/media/pci/tw68/tw68-video.c

---

## 4. PCIe у Waveshare CM4-DUAL-ETH-BOX-A (= CM4-DUAL-ETH-BASE у корпусі)

- За сніпетами сторінки Waveshare: ETH0 — рідний порт CM4, **ETH1 — RTL8111H «PCIe extended network port»**; на платі є **3 порти USB 3.2 Gen1**; живлення 7–36 В DC **[сніпет]**: https://www.waveshare.com/cm4-dual-eth-base.htm , https://www.waveshare.com/wiki/CM4-DUAL-ETH-BASE
  Один зі сніпетів називає ETH1 «USB extended ETH», тобто дані суперечливі. Для MINI-версії Waveshare явно пише «RTL8111H … ETH1 PCIe» **[сніпет]**: https://www.waveshare.com/wiki/CM4-DUAL-ETH-MINI
- CM4 має одну лінію PCIe Gen2 x1. Щоб на ній працювали і RTL8111H (PCIe), і USB 3.2 (на CM4 це майже завжди VL805 на PCIe), потрібен PCIe-комутатор (ASM1182e/ASM1184e). Так зроблено в Waveshare CM4-NVME-NAS-BOX (ASM1184e + VL805 + RTL8111) **[сніпет]**: https://www.waveshare.com/wiki/CM4-NVME-NAS-BOX , https://github.com/raspberrypi/rpi-eeprom/issues/416 . **Для DUAL-ETH-BASE наявність комутатора я не підтвердив** (сторінки Waveshare недоступні).
- Слот M.2 / mini-PCIe для DUAL-ETH-BASE у знайдених описах не згадується. M.2 B-key є у варіанті CM4-DUAL-ETH-4G/5G-BASE, але він під модем (USB) **[сніпет]**: https://www.waveshare.com/wiki/CM4-DUAL-ETH-4G/5G-BASE
- **Висновок:** вільної лінії PCIe для TW6869 практично немає, як і механічного слота в корпусі BOX-A. **Перевірити на пристрої:** `lspci -tv` (очікую комутатор ASMedia + `10ec:8168` + `1106:3483` VL805) і `lsusb -t` (чи порти USB — це xHCI VL805, а не dwc2). Для USB-граберів це навіть плюс: xHCI VL805 обслуговує ізохронний high-bandwidth потік значно краще за dwc2.

---

## 5. Живлення й пропускна здатність USB 2.0

- YUYV 720x576x2 байти x 25 кадрів/с = 20,7 МБ/с (у самому потоці з гасінням/заголовками трохи більше). Максимум ізохронного high-bandwidth ендпоінта в USB 2.0 — 3x1024 Б на мікрокадр = 24,576 МБ/с. Запас ~15 %, тож **на одному хост-контролері практично не вийде тримати два таких грабери одночасно** разом з іншим ізохронним трафіком. usbtv при цьому використовує alt setting 1. Для UTV007 чанк 256 Б несе 240 слів = 960 Б відео з 1024, тобто накладні витрати ≈6 %.
- Струм: пасивні EasyCAP-донгли живляться від шини; надійних специфікацій струму не знайшов (порядок ≈100–250 мА, **не перевірено**). Для CM4-DUAL-ETH-BASE з входом 7–36 В проблем не очікується.
- Режим `ALTERNATE` 720x288@50 не змінює пропускну здатність (ті самі байти, вдвічі частіші й менші буфери).

---

## 6. Невідоме / неперевірене

1. Реальна затримка UTV007 / STK1160 / EM2860 у мс ніде не опублікована; мої оцінки (≈40–50 мс стоково, ≈20–25 мс з патчем) виведено з коду драйверів. Внутрішню FIFO самих чипів (скільки рядків вони тримають до відправки) не документовано → **тільки замір**.
2. Чи продається зараз справжній UTV007 (а не MS2106) у конкретних лотах prom.ua — невідомо. Треба просити продавця показати `lsusb`/фото плати або купувати з можливістю повернення.
3. Архітектуру PCIe/USB у CM4-DUAL-ETH-BOX-A не підтверджено першоджерелом (сайт Waveshare недоступний з середовища) → `lspci -tv` на пристрої.
4. Полярність поля (`odd` → TOP чи BOTTOM) у патчі для usbtv і стабільність біта `odd` на реальному сигналі з камери треба перевірити.
5. Ціни й посилання взято з пошукової видачі й могли застаріти.
