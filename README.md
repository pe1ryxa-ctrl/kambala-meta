# kambala-meta — корінь екосистеми «Камбала»

Meta-репозиторій: протокол Архітектора (`CLAUDE.md`, генерується), глобальний SSOT (`Global_*`), `docs/`, опис екосистеми (`ecosystem.toml`).
Підпроєкти (`server`, `workstation`, `node-sim`, …) — окремі репозиторії всередині цієї папки, у `.gitignore`.

## Розгортання на Windows (один раз)
```powershell
New-Item -ItemType Directory -Force C:\Antigravity\Dev | Out-Null
git clone <url l2l1-kit>     C:\Antigravity\Dev\l2l1-kit
git clone <url kambala-meta> C:\Antigravity\Dev\Kambala
cd C:\Antigravity\Dev\Kambala
python C:\Antigravity\Dev\l2l1-kit\sync.py --git-init
# перенести існуючі документи:
Move-Item "$env:USERPROFILE\Desktop\Kambala\docs\*" C:\Antigravity\Dev\Kambala\docs\
```
`sync.py --git-init` створює `<P>\.agents\` (контракт L1, `/task`, правила-скелет, `agents.local.md`), `git init` у трьох підпроєктах,
і кладе глобальний `AGENTS.md` Gemini + ADLP у `%USERPROFILE%\.gemini\config\` (старий — у `.bak`).
Потрібен Python 3.11+ і Git for Windows. Не клади проєкт на Desktop/Documents — OneDrive ламає git.

## Після кожного оновлення kit
```powershell
git -C C:\Antigravity\Dev\l2l1-kit pull
cd C:\Antigravity\Dev\Kambala; python C:\Antigravity\Dev\l2l1-kit\sync.py
```

## Antigravity
Три воркспейси: `C:\Antigravity\Dev\Kambala\server`, `...\workstation`, `...\node-sim`. У кожному — команда `/task`.
Перевір, що Antigravity читає `%USERPROFILE%\.gemini\config\AGENTS.md` («які твої глобальні правила?»); якщо шлях інший — скажи Claude.

## Claude — перша сесія на цьому ПК
Claude Desktop → нова задача з лінком на цей комп'ютер → «Прочитай C:\Antigravity\Dev\Kambala\CLAUDE.md і роби бутстрап».
Claude звірить `Global_Context.md` з `docs\technical_specification.md`, заповнить крос-проєктні контракти і покаже перші ТЗ
(`KSIM-001`, `KSRV-001`, `KWS-001` — створення Holy Trinity).

## Що редагується де
- Протокол (шапка `AGENTS.md`, `/task`, шаблон задачі, глобальний `AGENTS.md` Gemini, `CLAUDE.md` крім §2/§6) — лише в `l2l1-kit`.
- `ecosystem.toml`, `claude.extra.md`, `Global_*`, `docs/` — тут.
- `<P>/.agents/agents.local.md`, `project-rules.md`, Holy Trinity, код — у репозиторії підпроєкту.
