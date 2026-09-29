# Kambala 2026-09-29, HIL KWS-022/030: SIGNED build of the workstation release on Gans's PC
# (Windows 11, PowerShell, Python 3.12+, internet, YubiKey #1). ASCII only on purpose (PowerShell 5.1).
# Same steps as build_release.sh (cloud, unsigned) plus the signature through release.py --key.
# Code: workstation branch release/0.0.2 (main 2e6432a without KWS-029, version 0.0.2 committed), -Ref 8463ef9.
# The release version must equal the committed one; HIL test releases 0.0.3+ need -TestVersion.
#
#   powershell -ExecutionPolicy Bypass -File pc_build_release.ps1 -Version 0.0.2
#   ... -Version 0.0.3 -TestVersion
#   ... -Version 0.0.4 -TestVersion -WheelsFrom $env:USERPROFILE\kws-rel\wheels-0.0.3   (negative HIL case KWS-030)
#   ... -Version 0.0.5 -TestVersion -BreakHomeUnit   (HIL KWS-022: home never starts after the switch -> rollback)
#
# Result in -Out: workstation-<v>.tgz, .tgz.sha256, .tgz.sig, workstation-<v>-release.json (sig+signer).
param(
  [Parameter(Mandatory = $true)][string]$Version,
  [string]$WsRepo = "C:\Antigravity\Dev\Kambala\workstation",
  [string]$ServerRepo = "C:\Antigravity\Dev\Kambala\server",
  [string]$Ref = "8463ef9",
  [string]$Out = "$env:USERPROFILE\kws-rel",
  [string]$WheelsFrom = "",
  [switch]$BreakHomeUnit,
  [switch]$TestVersion,
  [string]$Key = "$env:USERPROFILE\.ssh\id_kambala_master_1",
  [string]$Signer = "gans-master-1",
  [string]$Python = "python"
)
$ErrorActionPreference = "Stop"
function Fail($msg) { Write-Host "FAIL: $msg" -ForegroundColor Red; exit 1 }
function Check($what) { if ($LASTEXITCODE -ne 0) { Fail "$what (exit $LASTEXITCODE)" } }

if ($Version -notmatch '^\d+\.\d+\.\d+$') { Fail "Version must be N.N.N" }
# Windows OpenSSH first: Git's ssh-keygen cannot use the YubiKey (Global_Context C7a)
$env:PATH = "C:\Windows\System32\OpenSSH;" + $env:PATH
$sk = (Get-Command ssh-keygen).Source
if ($sk -notlike "C:\Windows\System32\OpenSSH\*") { Fail "ssh-keygen resolves to $sk, not System32\OpenSSH" }
if (-not (Test-Path $Key)) { Fail "key $Key not found" }
Write-Host "ssh-keygen: $sk"

$work = Join-Path $env:TEMP "kws-build-$Version"
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Force "$work\ws", "$work\srv", $Out | Out-Null
$wheels = Join-Path $Out "wheels-$Version"

Write-Host "== 1. clean copies (git archive)"
git -C $WsRepo fetch -q origin; Check "git fetch workstation"
git -C $WsRepo rev-parse -q --verify "$Ref^{commit}" | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "commit $Ref not found in $WsRepo (branch release/0.0.2 not pushed yet? git -C $WsRepo fetch origin release/0.0.2)" }
git -C $WsRepo archive -o "$work\ws.tar" $Ref; Check "git archive workstation $Ref"
tar -xf "$work\ws.tar" -C "$work\ws"; Check "tar ws"
git -C $ServerRepo fetch -q origin; Check "git fetch server"
git -C $ServerRepo archive -o "$work\srv.tar" origin/main; Check "git archive server"
tar -xf "$work\srv.tar" -C "$work\srv"; Check "tar srv"

Write-Host "== 2. version $Version"
$pp = "$work\ws\pyproject.toml"
$text = [IO.File]::ReadAllText($pp)
$m = [regex]::Match($text, '(?m)^version = "([^"]*)"')
if (-not $m.Success) { Fail "no version in pyproject.toml" }
if ($m.Groups[1].Value -eq $Version) {
  Write-Host "   pyproject.toml at ${Ref}: version = $Version (committed)"
} elseif (-not $TestVersion) {
  Fail "pyproject.toml at $Ref says $($m.Groups[1].Value), not $Version. A real release is built only from a commit with that version (-TestVersion is for HIL test releases 0.0.3+)"
} else {
  Write-Host "   HIL test release: pyproject.toml says $($m.Groups[1].Value); patched to $Version in the throw-away copy only (-TestVersion)" -ForegroundColor Yellow
  $text = [regex]::Replace($text, '(?m)^version = "[^"]*"', "version = `"$Version`"")
  [IO.File]::WriteAllText($pp, $text)
}

if ($BreakHomeUnit) {
  $hu = "$work\ws\deploy\kambala-home.service"
  $ht = [IO.File]::ReadAllText($hu)
  $ht2 = [regex]::Replace($ht, '(?m)-m kambala_ws\.home$', '-m kambala_ws.home_hil_broken')
  if ($ht2 -eq $ht) { Fail "BreakHomeUnit patch failed" }
  [IO.File]::WriteAllText($hu, $ht2)
  Write-Host "   HIL: kambala-home.service starts kambala_ws.home_hil_broken (health check must fail -> rollback)" -ForegroundColor Yellow
}
Write-Host "== 3. wheels (linux aarch64, CPython 3.13)"
if (Test-Path $wheels) { Remove-Item -Recurse -Force $wheels }
if ($WheelsFrom) {
  New-Item -ItemType Directory -Force $wheels | Out-Null
  Copy-Item "$WheelsFrom\*.whl" $wheels
  Write-Host "   wheels taken from $WheelsFrom (negative case)"
} else {
  & $Python "$work\ws\tools\build_wheels.py" -o $wheels; Check "build_wheels.py"
}

Write-Host "== 4. release.py build WITHOUT key -> check (mandatory before signing)"
$env:PYTHONPATH = "$work\srv\src"
$chk = Join-Path $work "check"
& $Python "$work\srv\tools\release.py" build workstation $Version --source "$work\ws" --wheels-dir $wheels --output-dir $chk --notes "HIL KWS-022/030: RM release layout"
Check "release.py build (unsigned check)"
$ca = Join-Path $chk "workstation-$Version.tgz"
$list = tar -tvzf $ca; Check "tar -tvzf"
$hard = $list | Where-Object { $_ -match '^h' }
if ($hard) { $hard | Select-Object -First 5 | Write-Host; Fail "hard-link entries in the archive: KWS-028 RM refuses them. Rebuild from a fresh git archive copy" }
$bad = $list | Where-Object { $_ -notmatch '^-' }
if ($bad) { $bad | Select-Object -First 5 | Write-Host; Fail "non-regular entries in the archive" }
$nox = $list | Where-Object { $_ -match '\.sh$' -and $_ -notmatch '^-rwx' }
if ($nox) { Write-Host "   WARNING: *.sh without +x (Windows build, README finding 6; rm_migrate.sh fixes it, auto-update does not):" -ForegroundColor Yellow; $nox | Select-Object -First 5 | Write-Host }
if ($list | Where-Object { $_ -match '/assets/bf/|/kambala_ws/home/fc\.py$' }) { Fail "KWS-029 files (assets/bf/, home/fc.py) in the archive: build from release/0.0.2, not main" }
$names = tar -tzf $ca
if ($names | Where-Object { $_ -notlike "workstation-$Version/*" }) { Fail "entries outside workstation-$Version/" }
$inner = (tar -xzOf $ca "workstation-$Version/release.json") -join "" | ConvertFrom-Json
if ($inner.component -ne "workstation" -or $inner.version -ne $Version) { Fail "release.json inside: $($inner | ConvertTo-Json -Compress)" }
$kw = @($names | Where-Object { $_ -like "workstation-$Version/wheels/kambala_ws-*" })
Write-Host "   entries: $($names.Count), all regular files (no hard links); wheel: $($kw -join ', ')"
if ($kw.Count -ne 1) { Fail "expected one kambala_ws wheel" }
if (-not $WheelsFrom -and $kw[0] -notlike "*/kambala_ws-$Version-*") { Fail "wheel is not of version $Version" }
$checkSha = (Get-FileHash -Algorithm SHA256 $ca).Hash.ToLower()

Write-Host "== 5. the same build WITH the key (touch the YubiKey when it blinks)"
& $Python "$work\srv\tools\release.py" build workstation $Version --source "$work\ws" --wheels-dir $wheels --output-dir $Out --notes "HIL KWS-022/030: RM release layout" --key $Key --signer $Signer
Check "release.py build (signed)"
Remove-Item Env:PYTHONPATH
$a = Join-Path $Out "workstation-$Version.tgz"
$sha = (Get-FileHash -Algorithm SHA256 $a).Hash.ToLower()
if ($sha -ne $checkSha) { Fail "signed archive $sha differs from the checked one $checkSha" }
$rel = Get-Content -Raw (Join-Path $Out "workstation-$Version-release.json") | ConvertFrom-Json
if (-not $rel.sig -or $rel.signer -ne $Signer) { Fail "release.json has no sig/signer" }
if (-not (Test-Path "$a.sig")) { Fail "no $a.sig" }
Write-Host "   signed archive = checked archive ($sha), signer $Signer"
Get-FileHash -Algorithm SHA256 "$wheels\*.whl" | Format-Table -AutoSize Hash, Path
Write-Host "archive sha256: $sha"
Write-Host "== DONE. Next (README step 2): scp to the VPS"
Write-Host "scp $a $a.sha256 $a.sig $(Join-Path $Out "workstation-$Version-release.json") root@10.66.0.1:/tmp/kws-rel/"
