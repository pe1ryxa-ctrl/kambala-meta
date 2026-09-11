# commit-meta.ps1 — коміт + пуш meta-репозиторію Kambala одним викликом.
# Використання:  .\commit-meta.ps1                       (повідомлення за замовчуванням)
#                .\commit-meta.ps1 "Global_Roadmap: Фаза 0 закрита"
param([string]$m = "meta: update Global_*")
git -C $PSScriptRoot add -A
git -C $PSScriptRoot commit -m $m
if ($LASTEXITCODE -eq 0) { git -C $PSScriptRoot push }
