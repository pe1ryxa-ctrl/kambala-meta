# Kambala — налаштування машини розробки

Що встановити й перенести на новий ПК. **Правило:** щойно Архітектор (Claude) або L1 починає користуватись новим інструментом, він одразу додає сюди рядок — що це, навіщо, як перевірити — і комітить у meta-репозиторій.

Стан зафіксовано на ПК Gans, 2026-09-15.

## 1. Інструменти

| Інструмент | Версія | Навіщо | Перевірка |
|---|---|---|---|
| Git for Windows (з Git Bash) | 2.55.0 | git; bash, `sed`, `awk`, `od`, `sha256sum` для верифікації; `pdftotext` (xpdf 4.06, `/mingw64/bin`) | `git --version`, `pdftotext -v` |
| OpenSSH client | 10.3p1 у Git Bash, 9.5p1 вбудований у Windows | `ssh`/`scp` до RPi 5 і до VPS через тунель | `ssh -V` |
| Python | 3.12.10 (`%LOCALAPPDATA%\Programs\Python\Python312`) | `l2l1-kit/sync.py`, `.venv` підпроєктів | `python --version` |
| PyMuPDF | 1.28.2 у `%USERPROFILE%\.venvs\kambala-architect` | рендер сторінок PDF: мануал FlyByIP не віддає кирилицю текстом, лише зображенням | `%USERPROFILE%\.venvs\kambala-architect\Scripts\python.exe -c "import pymupdf"` |
| WireGuard for Windows | wireguard-tools 1.0.20260223 | тунель `gans-pc` (`10.66.0.2`) → сервер `10.66.0.1` | `wg show` (від адміністратора) |
| Windows PowerShell | 5.1 | `deploy/push.ps1` підпроєктів | `$PSVersionTable.PSVersion` |
| Antigravity | — | L1 (Gemini) | — |
| Claude Desktop | — | L2 (Claude) | — |
| GitHub CLI `gh` | 2.100.0 (`C:\Program Files\GitHub CLI`, через `winget install --id GitHub.cli`) | створення репозиторіїв підпроєктів, робота з PR; після встановлення — `gh auth login` вручну (Gans) | `gh --version`, `gh auth status` |

Встановлення PyMuPDF у постійне середовище:
```
python -m venv %USERPROFILE%\.venvs\kambala-architect
%USERPROFILE%\.venvs\kambala-architect\Scripts\python.exe -m pip install pymupdf
```

## 2. Облікові дані й секрети — переносити вручну, ніколи в git

- **SSH-ключ** `%USERPROFILE%\.ssh\id_ed25519` (+ `.pub`) авторизований на RPi 5 (`gans@kambala-sim.local`) і на VPS (`root@10.66.0.1`). Альтернатива — новий ключ і додавання його в `authorized_keys` на обох машинах.
- **Конфіг WireGuard** тунелю `gans-pc` містить приватний ключ. Новий ПК з новим ключем означає новий пір на сервері; зміни WireGuard на VPS — лише за командою Gans.
- **`.env` підпроєктів** (не в git): `node-sim/.env` (`PI_HOST`, `PI_USER`); інші — за `.env.template` кожного підпроєкту.
- **Пам'ять Claude** `%USERPROFILE%\.claude\projects\C--Antigravity-Dev-Kambala-node-sim\memory\` — не в git.
- **Облікові записи:** GitHub `pe1ryxa-ctrl`; Google AI Pro (Antigravity).

## 3. Репозиторії

| Шлях | Remote |
|---|---|
| `C:\Antigravity\Dev\l2l1-kit` | `github.com/pe1ryxa-ctrl/l2l1-kit` |
| `C:\Antigravity\Dev\Kambala` (meta) | `github.com/pe1ryxa-ctrl/kambala-meta` |
| `C:\Antigravity\Dev\Kambala\node-sim` | `github.com/pe1ryxa-ctrl/kambala-node-sim` (приватний) |
| `C:\Antigravity\Dev\Kambala\server` | `github.com/pe1ryxa-ctrl/kambala-server` (приватний) |
| `C:\Antigravity\Dev\Kambala\workstation` | `github.com/pe1ryxa-ctrl/kambala-workstation` (приватний) |

Усі підпроєкти мають приватні репозиторії на GitHub (створено 2026-09-15 через `gh repo create`); L1 пушить у них після кожного коміту.

Порядок на новому ПК: клонувати kit і meta за тими самими шляхами → клонувати підпроєкти всередину meta → у корені meta запустити `python C:\Antigravity\Dev\l2l1-kit\sync.py` → у кожному підпроєкті `python -m venv .venv` і `.venv\Scripts\pip install -e .[dev]` → відновити `.env` із розділу 2.

## 4. Пастки цієї машини

- **Консоль Windows у `cp1252`:** Python-скрипти, що друкують кирилицю, падають з `UnicodeEncodeError` — задавати `PYTHONIOENCODING=utf-8`. У тестах вивід підпроцесів декодувати явно заданим кодуванням.
- **`python` у деяких оболонках** може вказувати на заглушку Microsoft Store — надійніше викликати повним шляхом.
- **PowerShell 5.1:** немає `&&`; `.ps1` з кирилицею зберігати в UTF-8 з BOM; не пропускати бінарні дані через конвеєр `|` чи `>` — PowerShell їх перекодовує.
- **ExecutionPolicy `Restricted`** за замовчуванням: скрипти запускати як `powershell -ExecutionPolicy Bypass -File <скрипт>`.
