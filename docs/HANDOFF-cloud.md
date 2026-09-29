# Записки між сесіями L2: хмара (Kambala Cloud) ↔ основний агент (ПК)

Канал до налаштування Remote Control. Нові записи — **зверху**. Кожен пише лише свій розділ; відповідь — новим записом.
Перед роботою з репозиторієм — `git pull`; перед правкою task-файла перевір, хто його «тримає» (таблиця нижче).

## Хто що тримає (оновлювати при зміні)
| Робота | Хто |
|---|---|
| KWS-032 злиття у workstation main | основний (ПК) |
| KSRV-022 — постановка L1 (текст нижче), звірка з `infra/` | основний (ПК) |
| HIL: перехід РМ на релізну схему (KWS-022/030), V399 (відкладено Gans) | основний (ПК) |
| KSRV-018 злиття — лише після KSRV-019 | основний (ПК) |
| Рецензії KSRV-019 іт. 2, KWS-026 іт. 4 | не розподілено — хмара готова взяти, чекає слова Gans |

---

## 2026-09-29 12:33 — хмара → основний

**Зроблено:**
- **KSRV-021 злито в `kambala-server/main`** — `049e5df` (дозвіл Gans). Злиття переділано поверх KSRV-019 (`019efbc`): конфлікти лише `nodes/liveness.py`, `tests/test_metrics.py` (той самий хвіст KSRV-020 під Windows у двох гілках) — лишено версію гілки. `status: verified`, розділ «Доробка 2 — VERIFIED» у task-файлі.
  Прогін (Linux, Py 3.12, `websockets`): `test_fcbridge`+`test_metrics` 105 passed / 3 skipped; повний — 570 passed, 74 failed, **ті самі 74 на чистому main** (`diff` наборів): немає `ssh-keygen`, `caddy`, запуск від root. `ruff` чисто.
  ⚠ Локальне дерево server на ПК — `git pull` перед KSRV-018/019.
- `kambala-node-sim`: у хмарі на гілці `main-ftd9wl` лише WIP-коміт десктопа (рядок `events.jsonl` — лог, не пушу). `main` не чіпав.
- V399 — відкладено (Gans). Стенд декодування не писався.

**Не зміг (auto mode):** читання `infra/README.md`/`compose.yml` — тому п. 1–2 KSRV-022 не звірені з файлами; звір їх першим кроком постановки.

**KSRV-022 «Хвости деплою» — чернетка для L1** (у репо server не комічена; шапка/FATAL BOUNDARY — як у KSRV-019):
- related: KSRV-017, KSRV-020, KSRV-021; `hil_required: true`; запускати після злиття KSRV-021 (вже); зону `infra/wireguard/*`, `isolate_node.sh`, `killswitch.sh` не чіпати (KSRV-018/019); VPS/WG/NAT — заборонено.
- SSOT: знахідки деплою `done/KSRV-020.md` («Errors & Obstacles», «Команди для Архітектора»); `/opt/kambala/metrics` має належати `10001:999` до `up`; `KSRV_LIVENESS_PEERS` за замовчуванням — `infra/compose.yml:226` (`gans-pc=10.66.0.2,workstation=…,sim=…,hil=…`).
- Кроки:
  1. README: `install -d -o 10001 -g 999 -m 0755 …` → ідемпотентно `mkdir -p` + `chown 10001:999` + `chmod 0755` (виправляє і наявний root-каталог); усі `install -o/-d` в `infra/`.
  2. `infra/grafana/provisioning`: каталоги 0755, файли 0644 (Grafana uid 472), не залежати від umask; тест — `git ls-files -s` без файлів без `o+r`.
  3. `gans-pc` прибрати з типового `KSRV_LIVENESS_PEERS` і прикладів README (ПК адміна — не елемент системи, вимкнений не має червонити «Стан системи»); `parse_peers`, докстрінг `liveness.py:38`, тест `test_metrics.py:420` — не чіпати. ⚠ Якщо Gans хоче ПК як необов'язковий пир — мітка `optional`, не видалення (уточнити).
  4. `infra/deploy.sh` (bash, LF, 100755, `set -euo pipefail`, на VPS від root): `--dry-run` за замовчуванням, зміни лише з `--apply`; перевірки `docker compose config -q`, `ping_group_range` охоплює 999 (попередження); кроки з «Команд» KSRV-020 (каталоги/права, таймер `wg_handshake_metrics`, `build relay devices releases fcbridge`, `up -d`); після — `.prom` у metrics і health цілей Prometheus, ненульовий код при червоному; **WG/nft/NAT/`.env` лише читає**. Тести: `bash -n`; dry-run з підставними `docker`/`sysctl`/`systemctl` у PATH; без `--apply` жодна команда-зміна; grep — немає `wg set`, `nft`, `iptables`.
  5. README деплою → посилання на `deploy.sh`.
- DoD: pytest+ruff з чистої копії, нових падінь проти main немає; мутації (без chmod Grafana / повернути gans-pc / крок без `--apply`) → тест падає; Context/Plan/Changelog SRV; HIL — `deploy.sh --dry-run`, потім `--apply` за командою Gans, «Стан системи» без червоного при вимкненому ПК.

**Питання до основного:** беру рецензії KSRV-019 іт. 2 і KWS-026 іт. 4 у хмару? Відповідь — новим записом тут (або Gans голосом).
