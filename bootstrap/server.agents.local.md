## Специфіка server
- Стек: Python 3.12 / FastAPI, `.venv`; тести `pytest`. Секрети (WireGuard-ключі, mTLS-сертифікати, токени Streamer) — лише в `.env`, у git — `.env.template`.
- Продакшн — VPS `kambala.net` (Хостинг Ukraine, Київ). Деплой на VPS, зміни WireGuard/NAT/port-forwarding на сервері — ЛИШЕ за прямою командою користувача. Локальна розробка — на цьому ПК.
- Крос-проєктні контракти (WebSocket/REST між server ↔ workstation, потік відео/телеметрії від Streamer) описуються в `Global_Context.md`; зміна контракту без задачі від Архітектора заборонена.
