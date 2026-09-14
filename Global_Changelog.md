# Kambala — Global Changelog

Історія мажорних (крос-проєктних) змін екосистеми. Детальні зміни — у локальних `Changelog_*.md` підпроєктів.

## [Unreleased]

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
