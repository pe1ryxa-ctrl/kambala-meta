# Kambala — Global Changelog

Історія мажорних (крос-проєктних) змін екосистеми. Детальні зміни — у локальних `Changelog_*.md` підпроєктів.

## [Unreleased]
- **Бойова траса керування працює (2026-09-16, HIL PASS KSIM-004 + KSRV-003):** TX12 → RPi 4 → WireGuard → VPS (релей) → RPi 5 у ролі MikroTik → FlyByIP-B → ELRS → борт; затримка через релей 67 мс медіана (пряма 51). Релей і піри задеплоєно на VPS (firewall: UDP 1313 з `wg0` перед SSH-ratelimit), RPi 5 — `deploy/wg-node/`, FlyByIP-B Remote IP → `10.66.0.1`.
- **node-sim KSIM-005 done (2026-09-16, HIL PASS):** RTSP `rtsp://<node>:8554/video0` H.264 з оверлеєм (годинник UTC, лічильник кадрів, стан CRSF і 16 каналів) через MediaMTX `node/sim-video` у браузер; сервіс `Type=simple`, пакет на RPi 5 у editable-режимі. Прототип Flight Display на RPi 4: GStreamer `v4l2h264dec` + `waylandsink`, 7 % CPU.
- **workstation KWS-004 done (2026-09-16, HIL PASS):** безпечний кадр до відновлення пульта, профілі пульта/борта за C5, майстер калібрування у веб-UI, прив'язка функцій — перевірено на RPi 5 з TX12 і Betaflight.
- **workstation KWS-003 done (2026-09-15, HIL PASS):** повне меню модуля ELRS TX у веб-UI сервісу `rc` через протокол параметрів CRSF по UDP (без Lua/пульта): дерево, запис із підтвердженням, команди з підтвердженням, ELRS-статус, телеметрія лінку, банери стану; цикли 3/3b — у режимі L2 fallback. Виміряно затримку керування (44 Гц 74 мс, 82 Гц 52 мс медіана), зафіксовано особливості MilELRS та FlyByIP-B.
- **Контракт C2-relay і три задачі в режимі L2 fallback (2026-09-15, квота L1 вичерпана):** `Global_Context` — C2-relay (піри `10.66.0.0/16`, релей кадр-у-кадр з джерела `10.66.0.1:1313`, гейт «оператор → вузол»), C5 (карта каналів + профілі борта/пульта, link-драйвери `elrs`/`sine.link`). **workstation KWS-004** (verified, HIL завтра): безпечний кадр до відновлення пульта, профілі пульта/борта за C5, `GET /inputs`/`/profiles`, майстер калібрування у веб-UI (монітор органів, майстер пульта, прив'язка функцій). **node-sim KSIM-004** (verified, HIL): RPi 5 у ролі MikroTik — `deploy/wg-node/` (wg0, forwarding, nftables «лише сервер», timesyncd). **server KSRV-003** (verified, деплой за командою Gans): релей керування + API `/nodes/*/control` + піри WireGuard у `infra/wireguard/` + сервіс `relay` у compose. Протокол l2l1-kit: `subagents: none` = заборона. RPi 4 (`kambala-ws.local`) прошито й підготовлено.

### Milestone
* 2026-09-16 — **перше наскрізне відео по бойовій трасі:** FPV-камера борта → VRX → Streamer (RTSP) → RPi 5 (роль MikroTik) → WireGuard → VPS MediaMTX → WebRTC → браузер оператора (KSRV-004 деплой); керування тією ж трасою через релей (KSRV-003, KSIM-004): Happymodel 915 200 Гц, затримка стіка 47 мс медіана.
* 2026-09-15 — **перше наскрізне керування на реальному залізі:** TX12 (USB) → `rc` (workstation, KWS-002) → FlyByIP-B → ELRS → приймач → Betaflight; failsafe при втраті пульта. Рішення C (власне РМ без модуля FlyByIP-A) доведено.
* node-sim емулює FlyByIP-B за виміряною семантикою (KSIM-003); контракт C1/C1a уточнено за залізом (RAW UDP, REST Streamer, два відеовходи).
* Інфраструктура VPS під git із закріпленням образів за дайджестом, розгорнуто (KSRV-002).
### Architecture
* Security baseline вузла: ізоляція MikroTik/WireGuard (лише сервер має доступ до вузла), пароль Streamer не потрібен; SSH Streamer — лише publickey.
* Lua-меню ELRS переноситься у веб-інтерфейс через протокол параметрів CRSF (KWS-003).

## [v0.2.0] - 2026-09-15
### Milestone
* **Фаза 0 закрита** (підтвердження Gans): Holy Trinity і скелети `server` (KSRV-001), `node-sim` (KSIM-001), `workstation` (KWS-001) — VERIFIED виконанням.
* node-sim: деплой-пайплайн на Raspberry Pi 5 однією командою з ПК, `-DryRun` без плати; перший HIL PASS 2026-09-11 (KSIM-002).
* Підпроєкти `server`, `node-sim`, `workstation` отримали приватні GitHub-репозиторії (`pe1ryxa-ctrl/kambala-*`).
### Architecture
* Задокументовано еталонний стан VPS `kambala.net`, WireGuard `10.66.0.0/16` і docker-стеку `/opt/kambala`.
* Ground Control — контейнер у наявному compose за Caddy, MediaMTX — окремий контейнер (2026-09-14).
* Керування з пульта — варіант C: власне робоче місце, CRSF over UDP (2026-09-15). Факти каналу FlyByIP за мануалом і ризик сумісності — `Global_Context.md`, C4.
### Process
* l2l1-kit: виконувані артефакти перевіряються парсингом або запуском; рев'ю L1 має доводити; видалення даних — ADLP; наявні тести — контракт; правка не існує, поки не в origin.

## [v0.1.0] - 2026-09-10
### Process
* Розгорнуто протокол L2/L1 (l2l1-kit): Claude = Architect, Gemini (Antigravity) = L1 Developer; задачі через `.agents/tasks/`, тригер `/task`.
