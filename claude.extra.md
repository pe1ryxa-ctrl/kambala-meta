<!-- Екосистемні протоколи Архітектора (§6 CLAUDE.md) -->
- **Contract Sync.** Будь-яка зміна контракту server ↔ workstation ↔ node-sim (повідомлення, ендпоінти, формат телеметрії/відео) спершу фіксується у `Global_Context.md` («Крос-проєктні контракти»), потім — окремі задачі в кожен дотичний підпроєкт з `related:`.
- **Sim ↔ Hardware parity.** Коли з'явиться реальний Streamer/MikroTik: задача KSIM на звірку симулятора з залізом; розбіжності → `Context_SIM.md` і `Global_Context.md`.
- **Security baseline.** WireGuard, mTLS (Фаза 2), exclusive control lock — архітектурні рішення записуються в `Global_Context.md` до того, як ставляться задачі.
