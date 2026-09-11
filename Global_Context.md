# Kambala — Global Context

> Чернетка від Архітектора за усними описами Gans (вересень 2026). **Першою дією Claude на Windows-ПК — звірити цей файл із `docs/technical_specification.md` і мануалом FlyByIP IP-Video v1.3, виправити й зняти цю примітку.**

## Екосистема
«Камбала» — розподілена система базування та запуску БпЛА (drone-in-a-box): віддалені вузли з відеостримерами й пусковими боксами, робоче місце оператора та центральний сервер, що зв'язує їх через VPN.

1.  **Віддалений вузол (Node)** — *залізо, пізніше підпроєкт `node`*
    *   **Роль:** Streamer Unit на CM4 FlyByIP (IP-відео + телеметрія) + 1..N пускових боксів на RPi Pico 2, з'єднаних по CAN; живлення/зв'язок — PoE-лінія 48–50 В. На вузлі — маршрутизатор MikroTik RB750UPr2 (WireGuard-клієнт до сервера; Streamer/FBI-B за ним, без RPi на вузлі).
    *   **Взаємодія:** відео й телеметрія (MAVLink) → через WireGuard-тунель на центральний сервер; команди запуску ← від оператора через сервер.

2.  **Node Simulator (`node-sim`)** — Raspberry Pi 5
    *   **Роль:** тимчасова заміна Streamer+MikroTik, поки залізо в дорозі: тест-патерн відео з годинником/секундоміром + MAVLink-телеметрія. Далі — постійний тестовий стенд.
    *   **Технології:** визначити в `Context_SIM.md` (Python; GStreamer/ffmpeg для відео; pymavlink).

3.  **Ground Control Server (`server`)** — VPS
    *   **Роль:** центральний вузол: WireGuard-тунелі до вузлів, NAT/port-forwarding, веб-інтерфейс Ground Control (Фаза 1 — для адміністратора/тестувальника), автентифікація, збереження стану.
    *   **Технології:** Python 3.12 / FastAPI; хостинг — Хостинг Ukraine, Shared CPU VPS 8G (4 vCPU / 8 GB / 70 GB NVMe, Київ); домен `kambala.net` (ukraine.com.ua, WHOIS privacy).
    *   **Взаємодія:** приймає потоки від вузлів; віддає відео/телеметрію в браузер і на workstation; у Фазі 2 — mTLS і exclusive control lock для пілотів.

4.  **Operator Workstation (`workstation`)** — Raspberry Pi 4, два дисплеї
    *   **Роль:** робоче місце оператора; ПЗ пишеться з нуля.
    *   **Взаємодія:** клієнт server (відео, телеметрія, керування).

5.  **QGroundControl plugin (`qgc-plugin`)** — Фаза 2
    *   **Роль:** кастомний плагін QGC для пілотів; mTLS; exclusive control lock.

## Ролі та AI-воркфлоу
| Хто | Роль |
|---|---|
| **Gans** | Керівник. Затверджує ТЗ, тригерить L1 (`/task <ID>`), тестує залізо (RPi 4/5, вузли), дає згоду на ADLP-дії та деплої. |
| **Claude** | **L2 Architect.** Планує, пише задачі у `<P>/.agents/tasks/<ID>.md`, верифікує по `git diff`, веде Global_* і `.agents/`. Протокол: `CLAUDE.md`. |
| **Gemini (Antigravity)** | **L1 Developer.** Один воркспейс = один підпроєкт. Реалізує, тестує, оновлює Holy Trinity, комітить, дописує Report. Контракт: `<P>/.agents/AGENTS.md`. |

- **SSOT:** Holy Trinity (`Context_X / Plan_X / Changelog_X`) веде L1; Global_* веде Claude. Plan містить лише беклог.
- **Задачі:** шаблон `.agents/TASK_TEMPLATE.md`; ID — `KSRV/KWS/KSIM/KNODE/KQGC-<NNN>`; файли комітяться в git підпроєкту; закриті — у `tasks/done/`.
- Ліміти Gemini спільні з екосистемою DDL — черга задач узгоджується Архітектором.

## Крос-проєктні контракти
<Заповнюється до перших продуктових задач: транспорт відео (RTSP/WebRTC/HLS?), телеметрія (MAVLink через UDP/TCP у тунелі), API server ↔ workstation, автентифікація. Кожна зміна тут — задачі в усі дотичні підпроєкти.>
