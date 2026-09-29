# Перехід РМ на релізну схему (HIL KWS-022/030, 2026-09-29)

Робоче місце оператора (RPi 4, Debian 13, Python 3.13.5, користувач `gans`, тунель `10.66.0.3`) переходить
зі старої розкладки (`~/kws` — звичайний каталог, служби з `~/kws-venv` + `PYTHONPATH=%h/kws/src`) на
релізну (KWS-022/030):

```
~/kws  ->  ~/kws-releases/0.0.2/workstation-0.0.2/      код релізу + .env, allowed_signers, events*.jsonl, profiles/ ...
                                   └── .venv/           пакет kambala_ws лише з колеса, --no-index
~/.config/systemd/user/kambala-{display,home,rc,ui,update}.service   ExecStart=%h/kws/.venv/bin/python -m ...
~/kws.pre-release-<дата-час>/   старий каталог, НЕ видаляється (відкат)
```

Порядок: **ПК** (збирання й підпис) → **VPS** (викладання, `recommend`) → **РМ** (перехід) → HIL-чекліст.
Код проєктів не змінюється; скрипти процедури — тут.

| Файл | Де запускати | Що робить |
|---|---|---|
| `pc_build_release.ps1` | ПК, PowerShell | чиста копія `git archive` → версія в копії → колеса → `release.py build` **без ключа** → обов'язкова перевірка (hardlink, структура, колесо) → той самий `build` **з ключем** YubiKey, звірка sha256 |
| `build_release.sh` | Linux / хмара | те саме без підпису (відтворення й перевірка; так зібрано все нижче) |
| `vps_publish_ws.sh` | VPS, root | перевірки (sha256, підпис проти `/opt/kambala/allowed_signers.d/allowed_signers`, tar) → том `kambala_releases_data` → `chown 10001:999` → `recommend` → `latest.json` і роздача архіву |
| `rm_migrate.sh` | РМ, `gans` | перехід (фази A–D нижче), ідемпотентний, при збої перемикання — автоматичний відкат |
| `rm_rollback.sh` | РМ, `gans` | повертає старий `~/kws`, старі юніти, labwc/pcmanfm, прибирає `allowed_signers`/`~/kws-releases`, якщо їх не було |
| `HIL-checklist.md` | — | перевірки після переходу: KWS-022/030/028, 023, 031, 032 (з `KWS_TIMING_TESTS=1`), 034 |
| `tests/run_fake_home.sh` (+ `stubs/`, `fake_server.py`) | Linux | прогін у фейковому HOME: щасливий шлях, збій кожного кроку, повтор, відкат, справжнє автооновлення |

Усі `.sh` — LF, `bash -n` і `shellcheck -S warning` чисті.

---

## Вихідні рішення і знахідки (прочитати до запуску)

1. **Код — workstation `2e6432a`** (рішення Gans 2026-09-29): там злито KWS-028 доробку 1, тож **РМ перевіряє
   підпис** кожного релізу автооновлення (`ssh-keygen -Y verify` проти `~/kws/allowed_signers`), пам'ятає
   відмови (одне завантаження відхиленого релізу), відхиляє hardlink-записи tar. Сам перехід `rm_migrate.sh`
   теж перевіряє підпис (крок A4) — перший реліз ставиться лише підписаним. ⚠ `2e6432a` містить і
   KWS-029 (`home/fc.py`, `/bf/*`, статус задачі `reported`, не перевірено) — див. «Відкриті питання».
2. **Компонент — `workstation`, не `ws`.** РМ питає `GET /releases/<component_id>/latest.json` з
   `component_id="workstation"` (`update/config.py:124`), архів мусить мати каталог `workstation-<v>/` і
   `release.json` з `"component": "workstation"` (`verifier.py`, `installer.check_release_json`), резервний
   шлях менеджера зашитий як `workstation-<v>` (`manager.py`). Реліз під `ws` РМ не побачить ніколи
   (404). `ws 0.0.1-test` на сервері лишається як є і нікого не стосується.
3. **Версія — `0.0.2`.** Порівняння — `verifier.is_newer_version`: у `.venv` релізу пакета `packaging`
   немає (перевірено: є лише `kambala-ws`, `pip`, `python-dotenv`), тож діє запасний розбір
   `_fallback_parse_semver`, який відкидає все після `-`: `0.0.1-test → (0,0,1)`. Звідси
   `0.0.1 > 0.0.1-test` — **False** (рівні), `0.0.2 > 0.0.1-test` — True, `0.0.3 > 0.0.2` — True (замір у
   `.venv` релізу). Якби `packaging` був, `Version("0.0.2")` порівнювався б із кортежем → `TypeError` →
   False; тому версії лише `N.N.N` (скрипти інших не приймають). У `pyproject.toml` `2e6432a` досі
   `0.0.1`; колесо й реліз мусять мати одну версію, тому скрипти збирання міняють рядок `version` **лише в
   тимчасовій копії** (з попередженням). Правильніше — окремий коміт `version = "0.0.2"` у workstation
   (тоді збирати з нього, `-Ref <хеш>`); див. «Відкриті питання».
4. **Hardlink-записи.** `release.py build` пише в tar записи-hardlink, якщо у файлів джерела є жорсткі
   посилання; самоперевірка `release.py` і сервер такий архів приймають, нова РМ відхиляє. Відтворено:
   джерело з `ln dep.whl deploy/dup.whl` → `hrw-r--r-- … wheels/python_dotenv-1.2.3-py3-none-any.whl link to
   workstation-0.0.2/deploy/dup.whl`, `release.py` rc=0. Тому: джерело — **лише свіжа копія `git archive`**
   (жорстких посилань не буває), колеса — у каталозі поза джерелом; **перед підписом обов'язково**
   `tar -tvzf workstation-<v>.tgz | grep '^h'` — порожньо (так роблять `build_release.sh`,
   `pc_build_release.ps1` крок 4, `vps_publish_ws.sh` і `rm_migrate.sh` A5). Хмарне збирання 0.0.2:
   159 записів, усі звичайні файли.
5. **`allowed_signers` — перший крок `rm_migrate.sh`** (за `deploy/README.md` «Довірені ключі на РМ»):
   з відкритих ключів YubiKey №1/№2 складається `~/kws/allowed_signers` (`gans-master-1 …`,
   `gans-master-2 …`, `chmod 644`), далі нею ж перевіряється підпис архіву. Файл лежить у старому `~/kws`,
   при переході копіюється в реліз разом із `.env` (стан машини); оригінал їде з `mv` у
   `~/kws.pre-release-*`. `rm_rollback.sh` видаляє його (або відновлює попередній, якщо був).
6. **Архів, зібраний на Windows, втрачає біти виконання** (Python на Windows не бачить `+x` у `.sh`, а
   `release.py` бере режим із `stat`). `~/.bash_profile` (KWS-014) запускає
   `~/kws/deploy/kambala-session-start.sh` **напряму** — без `+x` compositor після перезавантаження не
   стартує. `rm_migrate.sh` робить `chmod +x deploy/*.sh` і перевіряє кожен файл, на який посилаються
   `~/.bash_profile`, `~/.config/labwc/autostart` і `crontab` (B4). **Автооновлення так не робить** —
   після кожного автооновлення з Windows-збірки перевірити `test -x ~/kws/deploy/kambala-session-start.sh`
   до перезавантаження (чекліст 2.7). Сам факт на реальній Windows-збірці не перевірено (хмара без Windows):
   перевірити `tar -tvzf` після кроку 1 — у рядку `deploy/kambala-session-start.sh` має бути `-rwx`.
7. **Системні налаштування `install-rc.sh`** (`/etc/systemd/system/user@.service.d/kambala-rtprio.conf`,
   `usbhid.jspoll=1` у `cmdline.txt`) під час переходу **не чіпаються**: інсталятору передаються
   `KWS_RC_RT_PRIORITY=0 KWS_RC_SET_JSPOLL=0` (лише в його середовище; служби читають `.env`). Вони вже
   стоять на РМ з KWS-010; так перехід не змінює нічого поза `$HOME` і відкат повний.
8. `install-kiosk.sh` (режим приладу) не запускається — він уже застосований; його файли посилаються на
   `/home/gans/kws/...`, що після переходу веде в реліз (перевірка B4).

## Колеса (linux aarch64, CPython 3.13)

Зібрано `deploy/build-wheels.sh` (обгортка `tools/build_wheels.py`, KWS-030 — крос-збирання вже
підтримує: `pip download --platform linux_aarch64 / manylinux2014 / manylinux_2_17 / manylinux_2_28
--python-version 3.13 --abi cp313 --only-binary=:all:`), з чистої копії `2e6432a` + `version = "0.0.2"`:

| Колесо | Розмір | sha256 |
|---|---|---|
| `kambala_ws-0.0.2-py3-none-any.whl` | 2 405,0 КБ | `df6608c8f0e5f9e84117b1faedacc63c06a3cad809ed02a722c580854ed2ff06` |
| `python_dotenv-1.2.3-py3-none-any.whl` | 22,2 КБ | `904552145e8bfed22162c09dab1c2b9b54fefa7b23ba780f4f26ca0316b0f0d9` |

Єдина залежність — `python-dotenv`, чисто-Python колесо; проблем з aarch64 немає. Колесо `kambala_ws`
відтворюване (два збирання — однаковий sha256); колесо з ПК може відрізнятися (інша ОС) — не помилка, але
версія в імені мусить бути `0.0.2`.

**Архів** (хмара, без підпису): `workstation-0.0.2.tgz`, 5 813 465 байт, 159 записів (лише звичайні файли),
sha256 `b93791b7797b748270b047d59a354a39fcb278ffe3b038d1ba87ff245ed4e0b9`, `release.json` усередині
`{"component": "workstation", "version": "0.0.2"}`. Колеса й архіви (> 5 МБ) у репозиторій не покладено;
відтворення на Linux: `bash build_release.sh 0.0.2 --out <каталог>` (потрібні клони
`kambala-workstation`/`kambala-server`, PyPI, `python3.13`). На сервер іде **підписаний** архів із ПК —
його sha256 буде іншим (інша ОС), це нормально.

**HIL-колеса pytest** (лише для таймінгового тесту KWS-032 на РМ, у реліз не входять):
`pytest-9.1.1` `37a86b45efb9a47a61a36449063e8e18d0cab3161329fc099eb21783169c4f0c`, `pluggy-1.6.0`
`e920276dd6813095e9377c0bc5566d94c932c33b27a3e3945d8389c374dd4746`, `iniconfig-2.3.0`
`f631c04d2c48c52b84d0d0549c99ff3859c98df65b3101406327ecc7d53fbf12`, `packaging-26.3`
`d7193f7c8e4e93f444fde0262bf90af30e16fa0ad0ad44cb553c87339b23cd1c`, `pygments-2.21.0`
`2363c69b61c4a97c838da3b130dcd6468f4848992b21a82f2a63ec34377137d9` (усі `py3-none-any`, 1,8 МБ). ПК:
```powershell
python -m pip download pytest --only-binary=:all: --platform manylinux2014_aarch64 --platform any --python-version 313 --implementation cp --abi cp313 -d $env:USERPROFILE\kws-rel\hil-wheels
```

---

## Крок 1. ПК (PowerShell): збирання і підпис

Передумови: клони `C:\Antigravity\Dev\Kambala\workstation` і `...\server` (інакше `-WsRepo`/`-ServerRepo`),
Python 3.12+, інтернет, YubiKey №1, `%USERPROFILE%\.ssh\id_kambala_master_1` (заглушка ключа `-sk`) і
`id_kambala_master_{1,2}.pub`. Скрипт сам ставить системний OpenSSH першим у `PATH` і перевіряє це.

```powershell
cd <kambala-meta>\docs\hil\rm-release-migration
powershell -ExecutionPolicy Bypass -File .\pc_build_release.ps1 -Version 0.0.2
```

Усередині — рівно такі виклики `release.py` (формат з `release.py build --help`; `$work` — тимчасова копія):
```powershell
$env:PATH = "C:\Windows\System32\OpenSSH;" + $env:PATH      # Git ssh-keygen токен не бачить (C7a)
$env:PYTHONPATH = "$work\srv\src"
python "$work\srv\tools\release.py" build workstation 0.0.2 --source "$work\ws" --wheels-dir "$env:USERPROFILE\kws-rel\wheels-0.0.2" --output-dir "$work\check" --notes "HIL KWS-022/030: RM release layout"
#   ... перевірка: tar -tvzf <архів> — жодного рядка на 'h', усе під workstation-0.0.2/, одне колесо kambala_ws-0.0.2 ...
python "$work\srv\tools\release.py" build workstation 0.0.2 --source "$work\ws" --wheels-dir "$env:USERPROFILE\kws-rel\wheels-0.0.2" --output-dir "$env:USERPROFILE\kws-rel" --notes "HIL KWS-022/030: RM release layout" --key "$env:USERPROFILE\.ssh\id_kambala_master_1" --signer gans-master-1
```
Торкнутися YubiKey, коли блимає (Windows покаже вікно PIN/дотику).

**Перевірити:** `== DONE`, рядок `signed archive = checked archive (<sha256>)`, `signer gans-master-1`; у
`%USERPROFILE%\kws-rel`: `workstation-0.0.2.tgz`, `.tgz.sha256`, `.tgz.sig`, `workstation-0.0.2-release.json`
(з полями `sig`, `signer`). Додатково: `tar -tvzf $env:USERPROFILE\kws-rel\workstation-0.0.2.tgz | findstr kambala-session-start` —
біти `rwx` (див. знахідку 6; якщо `rw-` — не зупинка, `rm_migrate.sh` виправить, але записати).

Передати файли (PowerShell не розкриває `*` для `scp`, тому поіменно):
```powershell
$r = "$env:USERPROFILE\kws-rel"; $m = "<kambala-meta>\docs\hil\rm-release-migration"
ssh root@10.66.0.1 "mkdir -p /tmp/kws-rel"
scp "$r\workstation-0.0.2.tgz" "$r\workstation-0.0.2.tgz.sha256" "$r\workstation-0.0.2.tgz.sig" "$r\workstation-0.0.2-release.json" "$m\vps_publish_ws.sh" root@10.66.0.1:/tmp/kws-rel/
ssh gans@10.66.0.3 "mkdir -p ~/kws-migration"
scp "$m\rm_migrate.sh" "$m\rm_rollback.sh" "$env:USERPROFILE\.ssh\id_kambala_master_1.pub" "$env:USERPROFILE\.ssh\id_kambala_master_2.pub" gans@10.66.0.3:kws-migration/
```
(для KWS-032 ще `scp -r "$r\hil-wheels" gans@10.66.0.3:kws-migration/`). Архів на РМ не копіюється — РМ
завантажує його з сервера тунелем і так перевіряє саме опублікований.

## Крок 2. VPS (root): викладання і `recommend`

```bash
bash /tmp/kws-rel/vps_publish_ws.sh 0.0.2
```
**Перевірити:** `OK: sha256 …, signer gans-master-1, structure`; `Good "kambala-release" signature for
gans-master-1 with ED25519-SK key`; `recommend … HTTP 200` з `"signer":"gans-master-1"`; `latest.json` —
`0.0.2` з `sig`/`signer`; `served archive sha256 matches`; `== DONE`. Повторний запуск безпечний (файли
не переписуються); інший архів під тією ж версією — відмова.
З ПК: `curl.exe -s http://10.66.0.1/releases/workstation/latest.json` — `0.0.2`.

**Відкат VPS:** рекомендація — файл `<VOL>/workstation/recommended.json`. Було порожньо (компонент
новий) → `rm "$(docker volume inspect kambala_releases_data --format '{{.Mountpoint}}')/workstation/recommended.json"`
(latest → 404, РМ нічого не робить). Якщо скрипт зберіг `/root/kws-rel-recommended.json.before-<v>` —
повернути його на місце і `chown 10001:999`. Каталог `workstation/0.0.2/` можна лишити.

## Крок 3. РМ (`gans`): перехід

**3.0. До переходу** (лише читання; KWS-023 крок 1 — журнал 24.09, поки старі служби ще ті самі):
```bash
journalctl --user -u kambala-display --since "2026-09-24 10:15" --until "2026-09-24 10:17" --no-pager > ~/kws-migration/kws023_display_0924.txt
grep -cE 'Reconnecting in|Video pipeline exited' ~/kws-migration/kws023_display_0924.txt
systemctl --user is-active kambala-{display,home,rc,ui}; ls -la ~/kws; df -h ~
python3 -m venv /tmp/venv-probe && rm -rf /tmp/venv-probe && echo venv-ok
```
ARM вимкнено, борт знеструмлено або на землі: перехід на ~1–2 хв зупиняє `rc` (кадри RC) і екрани.

**3.1. Перехід** — від'єднано від SSH (обрив сесії не вб'є скрипт):
```bash
nohup bash ~/kws-migration/rm_migrate.sh 0.0.2 > ~/kws-migration/migrate.out 2>&1 &
tail -f ~/kws-migration/migrate.out
```
Фази й що має бути у виводі:
- **A** (нічого живого не змінює, крім `allowed_signers`): `old layout found, .env present` → `A1 not armed` →
  `A2 … ~/kws/allowed_signers written (2 lines)` + `-rw-r--r--` + два `sk-ssh-ed25519@openssh.com (sk)` →
  `A3 downloaded …`, `server recommends 0.0.2`, `sha256 …` → `A4 Good "kambala-release" signature for
  gans-master-1 with ED25519-SK key` → `A5 structure, release.json and wheel match`.
- **B** (готує `~/kws-releases/0.0.2/workstation-0.0.2`, живе не чіпає): розпакування, `chmod +x deploy/*.sh`,
  стан машини (`.env allowed_signers display_node.txt display_state.json events*.jsonl profiles/` — список
  `installer.copy_machine_state` + `display_state.json`, кожен звірено `cmp`/`diff`), `.venv` з коліс
  `--no-index`, перевірка імпорту як у `installer.install_release` (`-E`, модулі запуску, з цього `.venv`,
  версія `0.0.2`), `B4 … reference(s) resolved` (файли, які сесія бере з `~/kws`, є в релізі).
- **C** (перемикання): бекап `~/.config/systemd/user`, `~/.config/labwc`, `~/.config/pcmanfm`, linger →
  `~/.kws-migration/backup-<дата>`; зупинка 4 служб; `mv ~/kws ~/kws.pre-release-<дата-час>`;
  `ln -s …/workstation-0.0.2 ~/kws`; `~/kws-releases/current`; `deploy/install-{display,rc,home,ui,update}.sh`
  релізу; `daemon-reload`; рестарт 4 служб + `kambala-update`.
- **D** (перевірки): 5 юнітів `%h/kws/.venv/bin/python`, без `PYTHONPATH`, `enabled`; `systemd-analyze --user
  verify` чисто; 5 служб `active` (до 60 с); імпорт з `~/kws/.venv` → `0.0.2`, шлях у
  `…/workstation-0.0.2/.venv`. Кінець: `=== DONE: RM on release 0.0.2`.

Будь-який збій у A/B — `FAIL [A|B]: …` + `live system NOT touched`; збій у C/D — `FAIL [C]` +
`automatic rollback` + `rollback OK`. Повний журнал: `~/.kws-migration/migrate-<дата>.log`.

**3.2. Повторний запуск** після успіху: `bash ~/kws-migration/rm_migrate.sh 0.0.2` → `ALREADY MIGRATED, all
checks OK (nothing changed)` — лише перевірки D. Після збою в A/B — просто запустити ще раз (половинчастий
`~/kws-releases/0.0.2` прибирається сам).

**3.3.** Далі — `HIL-checklist.md` розділ 1 (обов'язково 1.10: перезавантаження).

## Відкат РМ

```bash
nohup bash ~/kws-migration/rm_rollback.sh > ~/kws-migration/rollback.out 2>&1 &
tail -f ~/kws-migration/rollback.out
```
Повертає: `~/kws` — знову старий каталог (з `~/kws.pre-release-*`; посилання видаляється, ціль — ні),
`~/.config/systemd/user`, `labwc`, `pcmanfm` — з бекапу (стан після переходу — поруч,
`*.after-migration`), `kambala-update` зупинено й вимкнено, `~/kws/allowed_signers` прибрано (якщо його не
було), `~/kws-releases` перенесено в `~/.kws-migration/kws-releases.rolled-back-*` (якщо його не було),
linger — як був, 4 старі служби `active`. Кінець: `=== ROLLED BACK`. Повтор — `already rolled back`.
Працює і після збою підготовки (тоді прибирає лише `allowed_signers` і `~/kws-releases`), і після обриву
скрипта посеред перемикання (стан `switching`). Під ARM відмовляє (`--force` — свідомо).

**Ручний відкат** (якщо скрипт недоступний), `<S>` — позначка з `~/.kws-migration/state` (`STAMP=`):
```bash
systemctl --user stop kambala-update kambala-rc kambala-home kambala-display kambala-ui
systemctl --user disable kambala-update
[ -L ~/kws ] && rm ~/kws                                # лише посилання; якщо ~/kws — каталог, нічого не видаляти
mv ~/kws.pre-release-<S> ~/kws
mv ~/.config/systemd/user ~/.kws-migration/backup-<S>/systemd_user.after-migration
cp -a ~/.kws-migration/backup-<S>/systemd_user ~/.config/systemd/user
mv ~/.config/labwc ~/.kws-migration/backup-<S>/labwc.after-migration && cp -a ~/.kws-migration/backup-<S>/labwc ~/.config/labwc
rm -f ~/kws/allowed_signers                            # якщо до переходу його не було (AS_BEFORE=absent у state)
systemctl --user daemon-reload
systemctl --user start kambala-rc kambala-home kambala-display kambala-ui
systemctl --user is-active kambala-rc kambala-home kambala-display kambala-ui
```
`~/kws-venv` протягом усієї процедури не змінюється — старі юніти запускаються з нього, як і раніше.

---

## Перевірка скриптів (хмара, фейковий HOME)

`bash tests/run_fake_home.sh <каталог збирання>` — стара розкладка `~/kws` відтворена з живого стану (src/,
deploy/, assets/, profiles/, pyproject.toml, events*.jsonl, display_state.json, display_node.txt,
flight-display.sh, rc.log, hdmitest, `.env`; `~/kws-venv`; старі юніти з `~/kws-venv` + `PYTHONPATH`;
`kambala-session.target`; `~/.bash_profile` і labwc `autostart` з `sysprep.py` KWS-014). Справжні: tar,
`python3.13 -m venv` + pip `--no-index`, `ssh-keygen` (тестові ключі ed25519 замість YubiKey),
`deploy/install-*.sh` релізу, `kambala_ws.update --once` релізу проти тестового сервера C7. Підставні:
`systemctl`, `loginctl`, `systemd-analyze` (перевіряє існування `ExecStart`/`WorkingDirectory`),
`crontab`, `python3` → 3.13 (+ збої). Результат прогону — у кінці розділу.

| Група | Сценарії |
|---|---|
| S1–S2 | перехід 0.0.2: посилання, старий каталог цілий, стан машини скопійовано й звірено, сміття старої розкладки не перенесено, `.venv` 0.0.2, 5 юнітів без `PYTHONPATH`, 5 `active`, `+x` у `kambala-session-start.sh`; повтор — `ALREADY MIGRATED`, нічого не змінено |
| S3 | справжній `kambala-update` після переходу: змінений 0.0.3 (3 цикли → 1 завантаження), непідписаний (2 → 1), без `allowed_signers` → відмова, файл повернуто → нова спроба → оновлено до 0.0.3 (0.0.2 збережено, стан перенесено); 0.0.4 з колесом 0.0.3 → відмова до перемикання |
| S4 | відкат після переходу й автооновлення → рівно вихідний стан (каталог, юніти, labwc, pcmanfm, служби, linger); повторний відкат; повторний перехід і відкат |
| F1–F13 | збої підготовки: версії немає на сервері; sha256; чужий ключ; немає `.pub` №2; hardlink у tar; колесо чужої версії; `venv`; `pip` (бите колесо); `autostart` посилається на `~/kws/flight-display.sh`; ARM; немає `.env`; повтор після збою; `rm_rollback.sh` на незайманій машині. Щоразу: жодного `stop`, `~/kws` — каталог, відрізняється лише `allowed_signers` (+ підготовлений `~/kws-releases`), `rm_rollback.sh` → рівно вихідний стан |
| C1–C7 | збої перемикання: `install-update.sh` (enable), `enable-linger`, `systemd-analyze verify`, служба не стає `active`, `daemon-reload` → автоматичний відкат → рівно вихідний стан; `--no-auto-rollback` + ручний відкат; скрипт убито посеред перемикання (обрив SSH/живлення) → повтор відмовляє вгадувати, `rm_rollback.sh` → вихідний стан |

Прогін 2026-09-29 (релізи 0.0.2/0.0.3/0.0.4 з `2e6432a`): **96 перевірок, 0 провалів** — повний перелік у
`tests/last-run.txt`. Тривалість ≈ 5 хв.

Окремо перевірено `vps_publish_ws.sh` з підставними `docker` і сервером на `127.0.0.1:8003`: публікація
й `recommend`; повтор (`already holds this archive`); інший архів під тією ж версією — відмова; підпис
чужим ключем — відмова.

## Відкриті питання

1. **Версія в `pyproject.toml`** — `0.0.1` у `2e6432a`. Збірка міняє її лише в тимчасовій копії (колесо й
   реліз `0.0.2` з коду `2e6432a`). Краще — коміт `version = "0.0.2"` у workstation main і збирання з нього
   (`-Ref`). Для 0.0.3–0.0.5 HIL — так само.
2. **KWS-029 у релізі.** `2e6432a` включає `b132d39` KWS-029 (статус `reported`, не перевірено): новий
   `home/fc.py`, маршрути `/bf/*`. Імпорт модулів запуску проходить; якщо KWS-029 не має їхати на РМ до
   вердикту — потрібен коміт «`cba0862` + KWS-028 доробка 1» без `b132d39` (рішення Архітектора); скрипти
   збирання приймають будь-який `-Ref`/`--ref`.
3. **Біти виконання у Windows-збірці** (знахідка 6) — ризик для **автооновлення** (не для переходу):
   `release.py` (KSRV) міг би ставити `0755` для `*.sh`, або блок `~/.bash_profile` (KWS-014) — викликати
   `bash "<шлях>"`. Потрібна задача KSRV або KWS.
4. **hardlink у `release.py build`** (знахідка 4; рецензія KWS-028 С-2) — задача KSRV: пакувати `LNKTYPE`
   як файл або відмовляти, і в C7a — дозволені типи записів.
5. **`component` `ws` vs `workstation`** — у `release.py` довідка й приклади говорять `ws`, а РМ — лише
   `workstation`. Узгодити в C7/`release.py --help`.
