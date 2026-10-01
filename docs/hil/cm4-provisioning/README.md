# Прошивка й провіжинг CM4 — ручний прохід (основа станції провіжингу)

> Global_Context «Станція прошивки й провіжингу» (рішення Gans 2026-10-01): процес автоматизується на окремій станції, що прошиває **кілька пристроїв одночасно**. Цей файл — покроковий запис першого ручного проходу (РМ-2, 2026-10-01): що зроблено, що спрацювало, де пастки. З нього пишеться сценарій.

## Залізо
- Модуль `CM4108016` (Wi-Fi/BT, 8 ГБ RAM, 16 ГБ eMMC; рішення Gans — бездротове вимикати), плата **Waveshare Compute Module 4 PoE Board Rev3** у корпусі CM4-IO-POE-BOX (2× HDMI, 4× USB 3.0 через VL805, гігабіт, PoE, DC 7–36 В, RTC CR2032).

## Етап 1 — запис eMMC (ПК Windows)
1. **BOOT:** перемичка на колодці 2×10 (біля DISP0/DISP1) — **верхній ряд GND ↔ BOOT**. Перемикача немає. Жовті перемички «Fit two jumpers for CAM1 and DISP0» не чіпати.
2. **USB для прошивки — micro-USB «SLAVE»** (не USB-C, його на платі немає); плата НЕ живиться від нього → порядок: перемичка BOOT → micro-USB SLAVE у ПК → **живлення DC**. Ознака правильного режиму: ACT блимнув один раз і згас; у Windows — пристрій `BCM2711 Boot` (`USB\VID_0A5C&PID_2711`).
3. `"C:\Program Files (x86)\Raspberry Pi\rpiboot.exe" -d msd` → eMMC з'являється як диск `RPi-MSD- 0001`, 14,6 ГБ (перевіряти номер диска — не системний!).
4. Raspberry Pi Imager 2.0.11.1: пристрій Raspberry Pi 4/CM4; ОС — Raspberry Pi OS (64-bit) trixie, повна (РМ-1: «Raspberry Pi reference 2026-06-18», ядро 6.18.39+rpt-rpi-v8, labwc 0.9.8, chromium 152); хост `kambala-ws2`, користувач `gans`, SSH лише за ключем — **3 ключі**: `id_ed25519` (автоматизація Архітектора без дотику YubiKey) + `id_kambala_master_1/2` (YubiKey, `sk-ssh-ed25519`); Wi-Fi порожній; Raspberry Pi Connect вимкнено; пояс `Europe/Kyiv`.
5. Після запису — зняти BOOT, від'єднати micro-USB, Ethernet, живлення.

## Бездротовий модуль
- Програмно: `config.txt` → `[all]` `dtoverlay=disable-wifi`, `dtoverlay=disable-bt`; перевірка — немає `wlan0` (`ip link`) і `/sys/class/bluetooth/hci0`.
- Апаратно (опція, рішення Gans «поки ні» 01.10): на тій самій колодці перемички **GND ↔ WIFI-EN**, **GND ↔ BT-EN** (за Waveshare Wiki: низький рівень вимикає модуль).

## Для автоматизації (станція)
- Кілька пристроїв одночасно: паралельні `rpiboot` (на Linux — `rpiboot -p <порт USB>`/серійний), запис `dd`/`bmaptool` без ручного вибору диска, журнал на пристрій.
- Ключі й налаштування — не через Imager, а через `firstrun`/`cloud-init` образу або власний етап після запису.

## Етап 2 — перший старт і доступ (РМ-2, 2026-10-01)
- Перший старт робить розширення ФС і **перезавантаження** — DHCP-оренда видається, потім ~30 с пристрій мовчить (ARP INCOMPLETE). Чекати, не діагностувати.
- Мережа першого старту: Ethernet напряму в RPi 5 стенда (статичний `eth0` без DHCP) — тимчасовий DHCP на RPi 5 без змін конфігурації: `sudo systemd-run --unit=tmp-dhcp-cm4 --property=RuntimeMaxSec=3600 /usr/sbin/dnsmasq --no-daemon --conf-file=/dev/null --port=0 --interface=eth0 --bind-interfaces --dhcp-range=192.168.13.100,192.168.13.110,255.255.255.0,60m --dhcp-host=<MAC>,192.168.13.105 --dhcp-leasefile=/tmp/ksim-dhcp.leases`; доступ `ssh -J root@10.66.0.1,gans@10.66.0.10 gans@192.168.13.105`. Без шлюзу/NAT — пристрій без інтернету (apt, NTP не працюють). **Для станції:** власний DHCP+NAT на порту провіжингу.
- Факт образу: Imager 2.0.11.1 поставив **«Raspberry Pi reference 2026-09-15»**, ядро 6.18.50, **labwc 0.20.1** (РМ-1: 2026-06-18, 6.18.39, labwc 0.9.8 — розкладка виводів KWS-038 перевірялась на 0.9.8 → HIL на РМ-2 обов'язковий), chromium 152 (як РМ-1); 8 ГБ RAM, eMMC 14 ГБ (зайнято 6,6). Часовий пояс з Imager **не застосувався** (`Europe/London`) — ставити явно.
- **Пароль користувача:** Imager заклав пароль, якого свідомо не задавали (`passwd -S` — дата збірки образу) → рішення Gans 01.10 «як на РМ-1»: `/etc/sudoers.d/010_gans-nopasswd` (`gans ALL=(ALL) NOPASSWD: ALL`, 0440, `visudo -cf`), пароль **заблоковано** `passwd -l gans`; SSH — лише ключі (`passwordauthentication no`, `kbdinteractiveauthentication no`) — як РМ-1. Для станції: ці кроки — у firstrun/образ, без введення пароля.
- **Бездротовий модуль:** `config.txt` → `[all]` `dtoverlay=disable-wifi`, `dtoverlay=disable-bt` (бекап `config.txt.bak-provision`) → після перезавантаження `ip -br link` = лише `lo eth0`, `/sys/class/bluetooth` порожній, `rfkill` порожній.
