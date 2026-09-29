# HIL-чекліст після переходу РМ на релізну схему

Виконується **після** успішного `rm_migrate.sh 0.0.2` (README, крок 3). Кроки взято з task-файлів
workstation `release/0.0.2` `8463ef9` (`.agents/tasks/KWS-022.md`, `KWS-028.md`, `KWS-030.md`, `KWS-023.md`,
`KWS-031.md`, `KWS-032.md`, `KWS-034.md`) і з `Plan_WS.md`. Позначення: **ПК** — PowerShell Gans,
**VPS** — `root@10.66.0.1`, **РМ** — `gans@10.66.0.3`. Кожен крок має очікуваний результат. Якщо результат
інший — зупинитися, зберегти вивід і журнал (`journalctl --user -u <юніт> --since "-15 min"`).

**KWS-029 (конфігуратор Betaflight, `/bf/*`, піктограма FC на плитках, `GET /fc`) на цьому релізі відсутній**
(рішення Gans 29.09: реліз для переходу — гілка `release/0.0.2` без `b132d39`) — його кроків у чеклісті немає і
не додавати; лише перевірка відсутності (1.12). HIL KWS-029 — після доробки (варіант A) на наступному релізі.

Версії для тестів збираються тим самим `pc_build_release.ps1` (README, крок 1) з тієї ж бази `8463ef9`; версія
`0.0.2` закомічена, тож для тестових `0.0.3`–`0.0.5` потрібен ключ `-TestVersion` (версія міняється лише в
тимчасовій копії):

| Версія | Команда на ПК | Для чого |
|---|---|---|
| `0.0.3` | `-Version 0.0.3 -TestVersion` | нормальне автооновлення, ARM, статуси (KWS-022/030) |
| `0.0.4` | `-Version 0.0.4 -TestVersion -WheelsFrom "$env:USERPROFILE\kws-rel\wheels-0.0.3"` | реліз із колесом іншої версії (KWS-030), поява `allowed_signers` (KWS-028) |
| `0.0.5` | `-Version 0.0.5 -TestVersion -BreakHomeUnit` | битий реліз: `home` не стартує → відкат за 60 с (KWS-022); його ж файли — для відмов підпису (KWS-028) |

Кожну версію викласти на VPS **без рекомендації**:
`bash /tmp/kws-rel/vps_publish_ws.sh <v> /tmp/kws-rel --no-recommend`. Рекомендувати — по черзі,
на відповідному кроці: `bash /tmp/kws-rel/vps_publish_ws.sh <v>` (той самий скрипт; повторний запуск
файлів не переписує).

---

## 1. KWS-022/030 — стан одразу після переходу (РМ)

| # | Команда | Очікувано |
|---|---|---|
| 1.1 | `systemd-analyze --user verify ~/.config/systemd/user/kambala-{display,home,rc,ui,update}.service; echo rc=$?` | жодного рядка про помилки, `rc=0` |
| 1.2 | `for u in display home rc ui update; do systemctl --user show -p Environment kambala-$u; done` | ніде немає `PYTHONPATH` |
| 1.3 | `~/kws/.venv/bin/python -I -c "import kambala_ws; print(kambala_ws.__file__, kambala_ws.__version__)"` | `/home/gans/kws/.venv/lib/python3.13/site-packages/kambala_ws/__init__.py 0.0.2` |
| 1.4 | `readlink -f ~/kws ~/kws/.venv; cat ~/kws-releases/current` | `…/kws-releases/0.0.2/workstation-0.0.2`, `…/workstation-0.0.2/.venv`, `0.0.2` |
| 1.5 | `systemctl --user is-active kambala-{display,home,rc,ui,update}` | 5 × `active` |
| 1.6 | `for u in home rc; do readlink /proc/$(systemctl --user show -p MainPID --value kambala-$u)/exe; done` | `/usr/bin/python3.13` (інтерпретатор із `.venv` → системний), cwd служб: `readlink /proc/<pid>/cwd` → `…/workstation-0.0.2` |
| 1.7 | `journalctl --user -u kambala-update --since "-10 min" --no-pager \| tail -20` | старт служби, без `Traceback`; поточна версія 0.0.2 = рекомендована → нічого не робить |
| 1.8 | `ls -l ~/kws/allowed_signers; cat ~/kws/allowed_signers` | `-rw-r--r-- gans`, рівно 2 рядки `gans-master-1 sk-ssh-ed25519@openssh.com …`, `gans-master-2 sk-ssh-ed25519@openssh.com …` |
| 1.9 | `test -x ~/kws/deploy/kambala-session-start.sh && echo x-ok` | `x-ok` |
| 1.10 | `sudo reboot`, після старту — екрани і `systemctl --user is-active kambala-{display,home,rc,ui,update}` | compositor піднявся сам (автологін tty1 → `~/.bash_profile` → `~/kws/deploy/kambala-session-start.sh`), Flight Display і кіоск на своїх виводах, 5 × `active` |
| 1.11 | `ls -ld ~/kws.pre-release-*; ls ~/kws-venv` | старий каталог і старе середовище на місці (не видаляти до кінця HIL) |
| 1.12 | `ls -d ~/kws/assets/bf ~/kws/.venv/lib/python3.13/site-packages/kambala_ws/home/fc.py; curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8082/bf/; grep -c KWS_FC_ ~/kws/.env` | реліз **без KWS-029**: `No such file or directory` ×2, `404`, `0` (якщо в `.env` є `KWS_FC_*` — не заважає, код їх не читає) |

## 2. KWS-022 — автооновлення на наступну версію, статуси, ARM (0.0.3)

| # | Дія | Очікувано |
|---|---|---|
| 2.1 | **РМ:** `journalctl --user -u kambala-update -f` (окремий термінал); на пульті **увімкнути ARM** | — |
| 2.2 | **VPS:** `bash /tmp/kws-rel/vps_publish_ws.sh 0.0.3` | `recommend … HTTP 200`, `latest.json = 0.0.3` |
| 2.3 | Чекати ≤ 60 с (`KWS_UPDATE_CHECK_S`) | у рядку стану «відкладено: політ», у журналі `deferred`; `readlink -f ~/kws` — усе ще 0.0.2; нічого не завантажено |
| 2.4 | Вимкнути ARM | за ≤ 60 с: «доступне 0.0.3» → «завантаження N %» → «перевірка суми» → «перевірка підпису» → «установка» → «перезапуск сервісів» → «перевірка» → «оновлено до 0.0.3»; від початку до «оновлено» — ≤ 60 с перевірки здоров'я |
| 2.5 | **РМ:** `readlink -f ~/kws; ~/kws/.venv/bin/python -I -c "import kambala_ws; print(kambala_ws.__version__)"; ls ~/kws-releases` | `…/0.0.3/workstation-0.0.3`, `0.0.3`; `0.0.2` і `0.0.3` обидва на місці (зберігаються 2) |
| 2.6 | **РМ:** `cmp ~/kws/.env ~/kws-releases/0.0.2/workstation-0.0.2/.env && cmp ~/kws/allowed_signers ~/kws-releases/0.0.2/workstation-0.0.2/allowed_signers && echo state-ok` | `state-ok` (стан машини перенесено) |
| 2.7 | **РМ:** `test -x ~/kws/deploy/kambala-session-start.sh && echo x-ok` | `x-ok`. **Якщо ні** (архів зібрано на Windows, див. README «Відомі ризики») — до будь-якого перезавантаження `chmod +x ~/kws/deploy/*.sh` і записати знахідку |
| 2.8 | **ПК:** `curl.exe -s http://10.66.0.1/components` | `workstation`: `version_current` 0.0.3, останній крок `complete`, `ok: true` |
| 2.9 | Домашній екран: журнал подій | рядки «Початок оновлення до 0.0.3», «Робоче місце оновлено до версії 0.0.3» |

## 3. KWS-028 — `allowed_signers` з'являється → нова спроба; KWS-030 — колесо чужої версії (0.0.4)

| # | Дія | Очікувано |
|---|---|---|
| 3.1 | **РМ:** `mv ~/kws/allowed_signers ~/allowed_signers.hil` | — |
| 3.2 | **VPS:** `bash /tmp/kws-rel/vps_publish_ws.sh 0.0.4` | recommend 200 (сервер перевіряє лише підпис і `release.json`, не колесо) |
| 3.3 | Чекати **5 хв**. **VPS:** `docker logs --since 6m releases 2>&1 \| grep -c 'GET /releases/workstation/0.0.4/workstation-0.0.4.tgz'` (якщо access-журналу `releases` немає — те саме по журналу Caddy) | **рівно 1** завантаження; **РМ:** журнал — один `verifying ok:false` «Файл довірених підписантів не знайдено», одна подія `err`, далі «уже відхилено» без завантаження; `~/kws` → 0.0.3, каталогу `~/kws-releases/0.0.4` немає |
| 3.4 | **РМ:** `mv ~/allowed_signers.hil ~/kws/allowed_signers` | — |
| 3.5 | Чекати ≤ 60 с | **нова спроба** (друге завантаження): підпис OK, структура OK, далі `installing ok:false` «Реліз 0.0.4 відхилено: Версія колеса (0.0.3) не збігається з версією релізу (0.0.4)…»; подія `err`; `readlink -f ~/kws` — 0.0.3; `~/kws-releases/0.0.4` видалено; 5 служб `active`, не перезапускались |
| 3.6 | **VPS:** `bash /tmp/kws-rel/vps_publish_ws.sh 0.0.3` | рекомендовано 0.0.3 знову; РМ: «актуальна версія» |

## 4. KWS-028 — непідписаний і змінений реліз відхиляються до розпакування; одне завантаження за 5 хв

Бойовий сервер такі релізи не рекомендує (fail-closed, KSRV-017), тому поведінку РМ перевіряємо локальним
тестовим сервером на самому РМ (`127.0.0.1:8099`), куди `kambala-update` направляється drop-in'ом systemd
(`.env` не змінюється). Файли — реліз `0.0.5` з бойового сервера (викладений `--no-recommend`).

```bash
# РМ
mkdir -p ~/hil028/releases/workstation/0.0.5 && cd ~/hil028/releases/workstation/0.0.5
curl -fsSO http://10.66.0.1/releases/workstation/0.0.5/workstation-0.0.5.tgz
curl -fsSO http://10.66.0.1/releases/workstation/0.0.5/release.json
cd ~/hil028 && python3 -m http.server 8099 --bind 127.0.0.1 > ~/hil028/http.log 2>&1 &
mkdir -p ~/.config/systemd/user/kambala-update.service.d
printf '[Service]\nEnvironment=KWS_UPDATE_SERVER_URL=http://127.0.0.1:8099\n' > ~/.config/systemd/user/kambala-update.service.d/hil028.conf
systemctl --user daemon-reload && systemctl --user restart kambala-update
```

| # | Дія | Очікувано |
|---|---|---|
| 4.1 | **Непідписаний:** `python3 -c 'import json; m=json.load(open("releases/workstation/0.0.5/release.json")); json.dump({"version":"0.0.5","url":"/releases/workstation/0.0.5/workstation-0.0.5.tgz","sha256":m["sha256"]}, open("releases/workstation/latest.json","w"))'` (у `~/hil028`), чекати 5 хв | `grep -c 'GET /releases/workstation/0.0.5/workstation-0.0.5.tgz' ~/hil028/http.log` → **1**; журнал: `verifying ok:false` «реліз не підписаний», одна подія `err`; `~/kws` → 0.0.3; `~/kws-releases/0.0.5` немає |
| 4.2 | **Змінений** (у `~/hil028`): `printf X >> releases/workstation/0.0.5/workstation-0.0.5.tgz; python3 -c 'import json,hashlib; p="releases/workstation/0.0.5/"; m=json.load(open(p+"release.json")); a=open(p+"workstation-0.0.5.tgz","rb").read(); json.dump({"version":"0.0.5","url":"/releases/workstation/0.0.5/workstation-0.0.5.tgz","sha256":hashlib.sha256(a).hexdigest(),"sig":m["sig"],"signer":m["signer"]}, open("releases/workstation/latest.json","w"))'; : > http.log`; чекати 5 хв | рівно **1** завантаження; «підпис недійсний» (`Could not verify signature` / `incorrect signature`); `~/kws` → 0.0.3 |
| 4.3 | `journalctl --user -u kambala-update --since "-15 min" \| grep -c Traceback` | `0` |
| 4.4 | **Прибрати:** `rm ~/.config/systemd/user/kambala-update.service.d/hil028.conf; rmdir ~/.config/systemd/user/kambala-update.service.d; systemctl --user daemon-reload; systemctl --user restart kambala-update; pkill -f "http.server 8099"; rm -rf ~/hil028` | служба знову ходить на `10.66.0.1` |
| 4.5 | **РМ:** `ssh-keygen -Y verify -f ~/kws/allowed_signers -I gans-master-1 -n kambala-release -s <(curl -fs http://10.66.0.1/releases/workstation/0.0.5/workstation-0.0.5.tgz.sig) < <(curl -fs http://10.66.0.1/releases/workstation/0.0.5/workstation-0.0.5.tgz)` | `Good "kambala-release" signature for gans-master-1 with ED25519-SK key SHA256:…` (**`ED25519-SK`** — ключ на токені) |

## 5. KWS-022 — битий реліз → відкат з причиною (0.0.5)

| # | Дія | Очікувано |
|---|---|---|
| 5.1 | **VPS:** `bash /tmp/kws-rel/vps_publish_ws.sh 0.0.5` | recommend 200 |
| 5.2 | Чекати ≤ 2 хв (журнал `kambala-update`) | установка 0.0.5 → перезапуск → `home` не стартує (`kambala_ws.home_hil_broken`) → за 60 с «відкат на 0.0.3: Таймаут перевірки (60 с): home /status недоступний, кіоск не видимий» (`rollback`, `ok:false`) |
| 5.3 | **РМ:** `readlink -f ~/kws; grep ExecStart ~/.config/systemd/user/kambala-home.service; systemctl --user is-active kambala-{display,home,rc,ui,update}` | `…/0.0.3/workstation-0.0.3`; `-m kambala_ws.home` (юніти відновлено); 5 × `active` |
| 5.4 | Журнал подій / `curl.exe -s http://10.66.0.1/components` | подія `err` «Відкат на 0.0.3: …»; на сервері крок `rollback` з причиною |
| 5.5 | Протягом години — жодної нової спроби 0.0.5 (кулдаун `failed_versions`) | журнал: «пропущено: версія 0.0.5 зазнала невдачі» |
| 5.6 | **VPS:** `bash /tmp/kws-rel/vps_publish_ws.sh 0.0.3` | рекомендація повернута на робочу версію |

## 6. KWS-023 — витримка попереджень, журнал, час першого кадру

Крок 1 з task-файлу («звідки взялося “потік відсутній” 24.09») виконується **до переходу** — README, крок 3.0.

| # | Дія | Очікувано |
|---|---|---|
| 6.1 | 10 хв звичайної роботи з потоком | на домашньому екрані попередження не блимають; у журналі немає пар «Попередження / знято» щосекунди (допустимі «Стан хитався: … N разів за M с») |
| 6.2 | Перемкнути вхід аналог ↔ HDMI 3–5 разів | на кожне перемикання **один** запис «Кадр після перемикання … з'явився за X с (запис входу A с; очікування потоку вузла B с, спроб WHEP N; від сесії до кадру C с)»; другого «за 0,4 с» немає; рядки — Архітектору |
| 6.3 | Вимкнути вхід / кабель на вузлі | «Flight Display: потік вузла … відсутній» через ≈ 5–6 с, не зникає, поки потоку немає; після відновлення зникає через ≈ 3 с |
| 6.4 | Борт `Telem Ratio = Std`, 5 хв; потім вимкнути живлення борта | пар «застаріла/відновлено» немає; «застаріла» через ≈ 5–6 с після порогу `rc`; при хитанні — рівно один «Телеметрія борта застаріла (нестабільно: N разів за M с)», після стійкого відновлення один «відновлено» |
| 6.5 | Розбіжність тумблера ARM і телеметрії | попередження **одразу** (ARM і аварійні стани без витримки) |
| 6.6 | Від'єднати сервер, `systemctl --user restart kambala-home`, потім повернути сервер | попередження на екрані через ≈ 5 с, нового рядка «Попередження: …» у журналі немає; після повернення — «Попередження знято: …» |
| 6.7 | На вузлі без потоку дочекатися «потік … відсутній», перемкнути вхід | попередження те саме, без пари «знято/піднято»; якщо новий вхід дає кадр — знімається через ≈ 3 с |

## 7. KWS-031 — журнал перемикання входу Streamer

| # | Дія | Очікувано |
|---|---|---|
| 7.1 | (а) Знеструмити вузол → спробувати перемкнути вхід | перемикачі заблоковані (вузол недоступний) — прийнятно; якщо натискання пройшло — у плитці «тайм-аут: вузол не відповів вчасно, стан входу невідомий», у журналі подій запис `err` (не «вузол недосяжний», уточнення вердикту) |
| 7.2 | (б) Висмикнути USB-захоплювач HDMI на Streamer → перемкнути на Аналог | аналог працює; у плитці й журналі `warn` «Увімкнено Аналог, але HDMI не вимкнено: HDMI: Streamer не бачить захоплювача (USB відключено?)»; рівно один запис на подію |

## 8. KWS-032 — запис Max Power ELRS, трасування, таймінговий тест

Борт знеструмлено або ARM вимкнено; пульт підключено. Модуль TX — через FlyByIP-B / S-Port (не USB РМ).

| # | Дія | Очікувано |
|---|---|---|
| 8.1 | Дописати в `~/kws/.env` `KWS_RC_PARAM_TRACE=1` (за бажання `KWS_RC_PARAM_TRACE_MAX=5000`), `systemctl --user restart kambala-rc` (ARM вимкнено). `.env` — у каталозі релізу; при наступному оновленні переїде разом із рядком | — |
| 8.2 | `curl -s 'http://127.0.0.1:8081/param-trace?limit=1' \| head -c 300`; `journalctl --user -u kambala-rc -f \| grep -E "PARAM (TX\|RX\|TLM)\|Re-sending WRITE\|Write of field"` | `"enabled": true` |
| 8.3 | Увімкнути борт, LQ > 0; `http://127.0.0.1:8081/`: `Dynamic` = `Off`, `Max Power` = 10 | — |
| 8.4 | `Max Power` **10 → 25 → 10**, пауза ≥ 5 с між кроками | toast «застосовано: фактично 25 мВт (телеметрія лінку)» / «… 10 мВт»; `GET /status` → `link_statistics.uplink_tx_power_mw` = вибраному; записати `writes_sent` (`WRITE ×N`) |
| 8.5 | Трасування сторінками по 200 (скрипт — `KWS-032.md`, «Доробка 1 … Пункт 3. HIL-крок 6»); паралельно `jitter_ms`/`current_rate_hz` з `/status` кожні 0,5 с | `current_rate_hz` 44 весь час; `jitter_ms` до і max під час знімання записати; якщо росте — повторити з `limit=100` |
| 8.6 | Таймінговий тест на РМ (див. нижче) | `1 passed` (без `KWS_TIMING_TESTS=1` — `skipped`) |
| 8.7 | `Max Power` = 10, прибрати `KWS_RC_PARAM_TRACE=1` з `~/kws/.env`, `systemctl --user restart kambala-rc` (ARM вимкнено) | трасування вимкнене |

Таймінговий тест `test_param_trace_http_does_not_stall_rc_loop` потребує `pytest`, якого в релізі немає
(інтернету на РМ немає). Окреме середовище, **не** `.venv` релізу; колеса — README, «HIL-колеса pytest»:

```bash
# РМ (колеса скопійовано в ~/kws-migration/hil-wheels)
python3 -m venv ~/kws-hil-venv
~/kws-hil-venv/bin/python -m pip install --no-index --find-links ~/kws-migration/hil-wheels --find-links ~/kws/wheels pytest python-dotenv
cd ~/kws && KWS_TIMING_TESTS=1 ~/kws-hil-venv/bin/python -m pytest tests/test_kws032_param_write.py -k param_trace_http_does_not_stall -v -p no:cacheprovider
# без змінної — має бути "1 skipped":
cd ~/kws && ~/kws-hil-venv/bin/python -m pytest tests/test_kws032_param_write.py -k param_trace_http_does_not_stall -q -p no:cacheprovider
```
Перевірено в хмарі (x86_64, Python 3.13, розпакований реліз 0.0.2): `1 passed, 28 deselected in 4.9s`.
Служби не зупиняти; прогнати, коли РМ «тихий» (без перемикань і оновлень).

## 9. KWS-034 — автомат плеєра домашнього екрана

Chromium DevTools → Network, фільтр `8889` (WHEP).

| # | Дія | Очікувано |
|---|---|---|
| 9.1 | Плеєр зупинено кліком → «Перезавантажити вузол» | жодного «Перемикання…»/«немає сигналу», 0 запитів на `:8889`; після повернення клік по кадру → відео актуального входу, один WHEP |
| 9.2 | Плеєр працює → перезавантаження вузла | відео повертається саме (≤ 10 с після `live`), у журналі «Відео вузла … повернулось» або кадр |
| 9.3 | Поки видно плашку провалу | WHEP-спроби не частіше ≈ 10 с |
| 9.4 | Аналог ↔ HDMI при працюючому і зупиненому плеєрі; HDMI без джерела | перемикання запускає відео і при зупиненому плеєрі; «немає сигналу» — лише після реальних 404 WHEP |
| 9.5 | «Повторити»: після провалу запису; після «немає сигналу» | провал запису → `POST /action/streamer-switch-input`; «немає сигналу» → лише WHEP |
| 9.6 | Клік по кадру під плашкою провалу | плеєр запускається |
| 9.7 | Одразу після перезавантаження Streamer | рядок «Аналог: у конфігурації вимкнено, фактично потік іде» і жовте попередження |
| 9.8 | Хитання телеметрії | «(нестабільно: …)» лише в першому рядку |

## 10. Завершення

- Результати — Архітектору (цей файл з позначками PASS/FAIL, виводи, журнали).
- Після PASS: `~/kws.pre-release-*` і `~/kws-venv` лишаються до окремого рішення (відкат `rm_rollback.sh`
  можливий, поки вони є). Якщо на РМ уже встановлено 0.0.3+, `rm_rollback.sh` все одно повертає старий
  каталог (не 0.0.2).
