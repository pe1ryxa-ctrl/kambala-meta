#!/bin/bash
# shellcheck disable=SC2088  # "~/kws" in messages is text for the operator, not a path
# Kambala 2026-09-29, HIL KWS-022/030: first switch of the operator workstation (RPi 4, user gans)
# from the old layout (~/kws is a plain directory) to the release layout:
#   ~/kws -> ~/kws-releases/<v>/workstation-<v>/   (code + its own .venv, installed from wheels only)
# Order follows workstation deploy/README.md (sections 2, 9, 12, 13) and installer.copy_machine_state.
#
#   rm_migrate.sh <version> [--pub1 FILE] [--pub2 FILE] [--archive FILE [--sha256 HEX]]
#                 [--no-auto-rollback] [--server URL]
#   --pub1/--pub2  public keys of YubiKey #1/#2 (default: id_kambala_master_{1,2}.pub next to this script)
#
# Phases:
#   A. checks; FIRST change: ~/kws/allowed_signers (gans-master-1/2, chmod 644, deploy/README.md
#      "Довірені ключі на РМ"); archive (download, sha256), ssh-keygen -Y verify against
#      ~/kws/allowed_signers, tar structure (regular files only: KWS-028 refuses hard links)
#   B. prepare ~/kws-releases/<v>/workstation-<v>: unpack, machine state, .venv from wheels (--no-index),
#      import check, check of files that ~/.bash_profile / labwc autostart / crontab take from ~/kws.
#      Nothing live is touched: a failure here only stops the script.
#   C. switch: backup of user units and labwc/pcmanfm config, stop services,
#      mv ~/kws ~/kws.pre-release-<stamp> (never deleted), ~/kws -> release, deploy/install-*.sh of the
#      release, systemd-analyze --user verify, 5 services active, import from ~/kws/.venv.
#      A failure here runs rm_rollback.sh (unless --no-auto-rollback).
# A second run after success only re-checks (phase D) and changes nothing.
# Log: ~/.kws-migration/migrate-<stamp>.log. Run detached: nohup bash rm_migrate.sh 0.0.2 > ... 2>&1 &
set -u
set -o pipefail
umask 022
trap '' HUP PIPE

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION=""
ARCHIVE=""
SHA_ARG=""
PUB1=""
PUB2=""
AUTO_ROLLBACK=1
SERVER_URL="${KWS_MIGRATE_SERVER_URL:-http://10.66.0.1}"
COMPONENT="workstation"
SIGNER_DEFAULT="gans-master-1"
PY="${KWS_MIGRATE_PYTHON:-python3}"
RC_STATUS_URL="${KWS_MIGRATE_RC_STATUS_URL:-http://127.0.0.1:8081/status}"
ACTIVE_TIMEOUT="${KWS_MIGRATE_ACTIVE_TIMEOUT:-60}"
SERVICES_OLD=(kambala-rc kambala-home kambala-display kambala-ui)
SERVICES_NEW=(kambala-rc kambala-home kambala-display kambala-ui kambala-update)
INSTALLERS=(display rc home ui update)   # deploy/README.md section 9 order, then section 12

while [ $# -gt 0 ]; do
  case "$1" in
    --archive) ARCHIVE="$2"; shift 2 ;;
    --sha256) SHA_ARG="$2"; shift 2 ;;
    --pub1) PUB1="$2"; shift 2 ;;
    --pub2) PUB2="$2"; shift 2 ;;
    --no-auto-rollback) AUTO_ROLLBACK=0; shift ;;
    --server) SERVER_URL="$2"; shift 2 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) if [ -z "$VERSION" ]; then VERSION="$1"; shift; else echo "extra argument $1" >&2; exit 2; fi ;;
  esac
done
if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "usage: $0 <version N.N.N> [options]  (see --help)" >&2
  exit 2
fi
PUB1="${PUB1:-$SCRIPT_DIR/id_kambala_master_1.pub}"
PUB2="${PUB2:-$SCRIPT_DIR/id_kambala_master_2.pub}"

LINK="$HOME/kws"
RELEASES="$HOME/kws-releases"
REL_TOP="$RELEASES/$VERSION"
REL_DIR="$REL_TOP/$COMPONENT-$VERSION"
MIG="$HOME/.kws-migration"
STATE="$MIG/state"
SYSTEMD_USER="$HOME/.config/systemd/user"
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$MIG" || { echo "cannot create $MIG" >&2; exit 1; }
LOG="$MIG/migrate-$STAMP.log"
DL="$MIG/dl-$VERSION"

# Output goes to the log file first; the terminal copy may vanish with SSH (never fatal).
say() { printf '%s %s\n' "$(date +%T)" "$*" >> "$LOG"; printf '%s\n' "$*" 2> /dev/null || true; }
run() { printf '%s $ %s\n' "$(date +%T)" "$*" >> "$LOG"; "$@" >> "$LOG" 2>&1; }
PHASE="A"
fail() {
  say "FAIL [$PHASE]: $*"
  local st; st="$(state_get STATUS)"
  if [ "$PHASE" = "C" ] && { [ "$st" = switching ] || [ "$st" = switched ]; }; then
    state_set STATUS failed_switch
    if [ "$AUTO_ROLLBACK" = 1 ]; then
      say "== automatic rollback: bash $SCRIPT_DIR/rm_rollback.sh --auto"
      if bash "$SCRIPT_DIR/rm_rollback.sh" --auto >> "$LOG" 2>&1; then
        say "   rollback OK: old ~/kws and old units are back (details in $LOG)"
      else
        say "   ROLLBACK FAILED - see $LOG and README 'Manual rollback'"
      fi
    else
      say "   left as is (--no-auto-rollback); to return: bash $SCRIPT_DIR/rm_rollback.sh"
    fi
  else
    case "$st" in preparing|prepared|signers_placed) state_set STATUS failed_prepare ;; esac
    say "   live system NOT touched: ~/kws, units and services are as before"
    if [ "${AS_PLACED:-0}" = 1 ]; then
      say "   (~/kws/allowed_signers stays: state for the next attempt, unused by the old code; rm_rollback.sh removes it)"
    fi
  fi
  say "log: $LOG"
  exit 1
}
ok() { say "   OK: $*"; }
state_set() {  # key value; the state file is sourced by rm_rollback.sh
  local k="$1" v="$2" tmp="$STATE.tmp"
  { [ -f "$STATE" ] && grep -v "^$k=" "$STATE"; printf "%s=%q\n" "$k" "$v"; } > "$tmp" && mv -f "$tmp" "$STATE"
}
state_get() { [ -f "$STATE" ] && sed -n "s/^$1=//p" "$STATE" | tail -n 1; }

# Import check the same way installer.install_release does it (-E, entry-point modules, from this .venv,
# distribution version == release). $1 = venv dir as the services see it.
import_check() {
  local venv="$1"
  "$venv/bin/python" -E -c '
import sys, pathlib, importlib.metadata
import kambala_ws, kambala_ws.__main__
import kambala_ws.home.service, kambala_ws.home.web, kambala_ws.home.__main__
import kambala_ws.rc.sender, kambala_ws.rc.__main__
import kambala_ws.display
import kambala_ws.kiosk.service, kambala_ws.kiosk.__main__
import kambala_ws.update.manager, kambala_ws.update.__main__
v_dir = pathlib.Path(sys.argv[1]).resolve()
loc = pathlib.Path(kambala_ws.__file__).resolve()
assert v_dir in loc.parents, f"kambala_ws imported from {loc}, not from {v_dir}"
dist_v = importlib.metadata.version("kambala-ws")
assert dist_v == sys.argv[2], f"installed kambala-ws {dist_v}, release {sys.argv[2]}"
assert kambala_ws.__version__ == sys.argv[2], f"__version__ {kambala_ws.__version__}"
print(dist_v, loc)
' "$venv" "$VERSION"
}

wait_active() {  # units...; waits up to ACTIVE_TIMEOUT s for all of them
  local deadline=$(( $(date +%s) + ACTIVE_TIMEOUT )) u bad
  while :; do
    bad=""
    for u in "$@"; do systemctl --user is-active --quiet "$u" || bad="$bad $u"; done
    [ -z "$bad" ] && return 0
    [ "$(date +%s)" -ge "$deadline" ] && { say "   not active after ${ACTIVE_TIMEOUT}s:$bad"; return 1; }
    sleep 2
  done
}

arm_check() {  # refuse while the aircraft is armed (same rule as check_arm_gate); unreachable rc = not armed
  "$PY" - "$RC_STATUS_URL" << 'EOF'
import json, sys, urllib.request
try:
    with urllib.request.urlopen(sys.argv[1], timeout=2) as r:
        d = json.loads(r.read().decode("utf-8"))
except Exception as e:
    print(f"rc status unavailable ({e.__class__.__name__}) - treated as not armed"); sys.exit(0)
t = d.get("telemetry") if isinstance(d, dict) else None
fm = t.get("flight_mode") if isinstance(t, dict) else None
if d.get("arm_safe") is False or (isinstance(fm, dict) and fm.get("armed") is True):
    print("ARMED"); sys.exit(1)
print("not armed")
EOF
}

# Phase D: checks after the switch (also the whole job of a repeated run)
verify_switched() {
  local u f rc=0 venv_real out
  say "== D1. units: files, %h/kws/.venv, no PYTHONPATH"
  for u in "${SERVICES_NEW[@]}"; do
    f="$SYSTEMD_USER/$u.service"
    [ -f "$f" ] || { say "   missing $f"; rc=1; continue; }
    grep -q '^ExecStart=%h/kws/\.venv/bin/python -m kambala_ws' "$f" || { say "   $u: ExecStart is not %h/kws/.venv/bin/python"; rc=1; }
    if grep -q 'PYTHONPATH' "$f"; then say "   $u: PYTHONPATH in unit"; rc=1; fi
    systemctl --user is-enabled --quiet "$u" || { say "   $u: not enabled"; rc=1; }
  done
  [ "$rc" = 0 ] && ok "5 unit files rendered and enabled"
  say "== D2. systemd-analyze --user verify"
  local files=()
  for u in "${SERVICES_NEW[@]}"; do files+=("$SYSTEMD_USER/$u.service"); done
  if run systemd-analyze --user verify "${files[@]}"; then ok "verify clean"
  else say "   systemd-analyze --user verify failed (output in $LOG)"; rc=1; fi
  say "== D3. services active (up to ${ACTIVE_TIMEOUT}s)"
  if wait_active "${SERVICES_NEW[@]}"; then ok "${SERVICES_NEW[*]} active"; else rc=1; fi
  for u in "${SERVICES_NEW[@]}"; do
    if systemctl --user show -p Environment "$u" 2>> "$LOG" | grep -q PYTHONPATH; then say "   $u: PYTHONPATH in the running environment"; rc=1; fi
  done
  say "== D4. import from ~/kws/.venv"
  venv_real="$(readlink -f "$LINK/.venv")"
  if out="$(import_check "$LINK/.venv" 2>> "$LOG")"; then ok "kambala-ws $out"
  else say "   import check from $LINK/.venv failed (see $LOG)"; rc=1; fi
  case "$venv_real" in "$REL_DIR/.venv") ;; *) say "   ~/kws/.venv resolves to $venv_real, expected $REL_DIR/.venv"; rc=1 ;; esac
  [ "$(cat "$RELEASES/current" 2> /dev/null)" = "$VERSION" ] || { say "   $RELEASES/current is not $VERSION"; rc=1; }
  return "$rc"
}

say "=== rm_migrate $VERSION  $(date -Is)  user $(id -un)  log $LOG"

# ---------------------------------------------------------------- phase A: checks and archive
PHASE="A"
if [ "$(id -u)" = 0 ] && [ "${KWS_MIGRATE_ALLOW_ROOT:-0}" != 1 ]; then fail "run as the workstation user (gans), not root"; fi
for c in "$PY" tar sha256sum stat ssh-keygen systemctl systemd-analyze loginctl; do
  command -v "$c" > /dev/null 2>&1 || fail "command not found: $c"
done
rm -rf "$MIG/venv-probe"
"$PY" -m venv "$MIG/venv-probe" > /dev/null 2>&1 || fail "$PY -m venv does not work (Debian: python3-venv / ensurepip)"
rm -rf "$MIG/venv-probe"

if [ -L "$LINK" ]; then
  cur="$(readlink -f "$LINK")"
  if [ "$cur" = "$(readlink -f "$REL_DIR" 2> /dev/null || echo "$REL_DIR")" ] && [ "$(state_get STATUS)" = "done" ]; then
    say "== ~/kws already -> $cur: migration to $VERSION was done ($(state_get STAMP)); re-checking only"
    PHASE="D"
    if verify_switched; then say "=== ALREADY MIGRATED, all checks OK (nothing changed)"; exit 0; fi
    say "=== ALREADY MIGRATED, but checks FAILED (nothing changed; see $LOG). Rollback: bash $SCRIPT_DIR/rm_rollback.sh"
    exit 1
  fi
  fail "~/kws is already a link to $cur (state: $(state_get STATUS)); this script only migrates the old plain directory"
fi
[ -d "$LINK" ] || fail "$LINK does not exist or is not a directory"
[ -f "$LINK/.env" ] || fail "$LINK/.env not found (installers need it)"
[ -d "$LINK/src/kambala_ws" ] || [ -f "$LINK/pyproject.toml" ] || fail "$LINK does not look like the old workstation directory"
case "$(state_get STATUS)" in
  switching|switched|failed_switch) fail "state $STATE says '$(state_get STATUS)' but ~/kws is a directory: finish or check rm_rollback.sh first" ;;
esac
if ls -d "$HOME"/kws.pre-release-* > /dev/null 2>&1; then
  say "   note: an older $(ls -d "$HOME"/kws.pre-release-* | tr '\n' ' ')exists (not touched)"
fi
avail_kb="$(df -Pk "$HOME" | awk 'NR==2 {print $4}')"
[ "${avail_kb:-0}" -ge 409600 ] || fail "less than 400 MB free in $HOME (${avail_kb} KB)"
ok "old layout found, .env present, ${avail_kb} KB free"

say "== A1. arm gate"
arm_out="$(arm_check 2>&1)" || fail "rc reports ARMED - not while flying ($arm_out)"
ok "$arm_out"

# A new migration cycle starts here (first run, or after rm_rollback.sh): facts for the rollback.
case "$(state_get STATUS)" in
  ""|rolled_back)
    : > "$STATE"
    if [ -e "$RELEASES" ]; then state_set RELEASES_PREEXISTED 1; else state_set RELEASES_PREEXISTED 0; fi
    if [ -f "$LINK/allowed_signers" ]; then
      cp -p "$LINK/allowed_signers" "$MIG/allowed_signers.before-$STAMP"
      state_set AS_BEFORE "$MIG/allowed_signers.before-$STAMP"
    else
      state_set AS_BEFORE absent
    fi
    ;;
esac

say "== A2. FIRST change: ~/kws/allowed_signers (C7a signers gans-master-1/2; deploy/README.md 'Довірені ключі на РМ')"
for f in "$PUB1" "$PUB2"; do [ -f "$f" ] || fail "public key $f not found (scp id_kambala_master_{1,2}.pub from the PC next to this script)"; done
AS_NEW="$MIG/allowed_signers.new"
{ printf 'gans-master-1 '; cut -d' ' -f1,2 "$PUB1"
  printf 'gans-master-2 '; cut -d' ' -f1,2 "$PUB2"; } > "$AS_NEW" || fail "cannot compose allowed_signers"
"$PY" - "$AS_NEW" << 'EOF' || fail "allowed_signers content is wrong (see $LOG)"
import base64, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
assert len(lines) == 2, f"{len(lines)} lines"
for want, ln in zip(("gans-master-1", "gans-master-2"), lines):
    name, ktype, key = ln.split(" ")
    assert name == want, name
    assert ktype in ("sk-ssh-ed25519@openssh.com", "ssh-ed25519"), ktype
    assert base64.b64decode(key, validate=True)[4:4 + len(ktype)] == ktype.encode(), "key blob type"
    print(name, ktype, "(sk)" if ktype.startswith("sk-") else "(NOT a token key: test only)")
EOF
if [ -f "$LINK/allowed_signers" ] && cmp -s "$AS_NEW" "$LINK/allowed_signers"; then
  rm -f "$AS_NEW"
  ok "~/kws/allowed_signers already has these two keys"
else
  chmod 644 "$AS_NEW" && mv -f "$AS_NEW" "$LINK/allowed_signers" || fail "cannot write $LINK/allowed_signers"
  ok "~/kws/allowed_signers written (2 lines)"
fi
AS_PLACED=1
[ "$(stat -c %a "$LINK/allowed_signers")" = 644 ] || fail "~/kws/allowed_signers is not 644"
say "   $(ls -l "$LINK/allowed_signers")"
case "$(state_get STATUS)" in failed_prepare|preparing|prepared) ;; *) state_set STATUS signers_placed ;; esac

say "== A3. archive"
mkdir -p "$DL" || fail "mkdir $DL"
META=""
if [ -z "$ARCHIVE" ]; then
  base="$SERVER_URL/releases/$COMPONENT/$VERSION"
  ARCHIVE="$DL/$COMPONENT-$VERSION.tgz"
  META="$DL/release.json"
  rm -f "$DL"/*
  run "$PY" - "$base" "$DL" "$COMPONENT-$VERSION.tgz" << 'EOF' || fail "download from $SERVER_URL/releases/$COMPONENT/$VERSION/ failed"
import sys, urllib.request, shutil
base, dst, arc = sys.argv[1:4]
for name in ("release.json", arc, arc + ".sig"):
    with urllib.request.urlopen(f"{base}/{name}", timeout=60) as r, open(f"{dst}/{name}.part", "wb") as f:
        shutil.copyfileobj(r, f)
    shutil.move(f"{dst}/{name}.part", f"{dst}/{name}")
    print("downloaded", name)
EOF
  ok "downloaded $base/{release.json,$COMPONENT-$VERSION.tgz,.sig}"
  lat="$("$PY" -c 'import json,sys,urllib.request; print(json.load(urllib.request.urlopen(sys.argv[1], timeout=10)).get("version"))' "$SERVER_URL/releases/$COMPONENT/latest.json" 2>> "$LOG")"
  if [ "$lat" = "$VERSION" ]; then ok "server recommends $VERSION"
  else say "   note: latest.json recommends '${lat:-none}', not $VERSION (kambala-update will follow the server)"; fi
else
  [ -f "$ARCHIVE" ] || fail "archive $ARCHIVE not found"
  ARCHIVE="$(cd "$(dirname "$ARCHIVE")" && pwd)/$(basename "$ARCHIVE")"
  for cand in "${ARCHIVE%.tgz}-release.json" "$(dirname "$ARCHIVE")/release.json"; do
    if [ -f "$cand" ]; then META="$cand"; break; fi
  done
fi
[ "$(basename "$ARCHIVE")" = "$COMPONENT-$VERSION.tgz" ] || fail "archive name must be $COMPONENT-$VERSION.tgz"

meta_get() { [ -n "$META" ] && "$PY" -c 'import json,sys; v=json.load(open(sys.argv[1])).get(sys.argv[2]); print(v if v is not None else "")' "$META" "$1"; }
EXP_SHA="$SHA_ARG"
[ -n "$EXP_SHA" ] || EXP_SHA="$(meta_get sha256)"
if [ -z "$EXP_SHA" ] && [ -f "$ARCHIVE.sha256" ]; then EXP_SHA="$(awk '{print $1; exit}' "$ARCHIVE.sha256")"; fi
[ -n "$EXP_SHA" ] || fail "no expected sha256 (release.json, $ARCHIVE.sha256 or --sha256)"
ACT_SHA="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
[ "$ACT_SHA" = "$EXP_SHA" ] || fail "sha256 mismatch: expected $EXP_SHA, got $ACT_SHA"
ok "sha256 $ACT_SHA"

say "== A4. signature: ssh-keygen -Y verify -f ~/kws/allowed_signers -I <signer> -n kambala-release"
SIGNER="$(meta_get signer)"; SIGNER="${SIGNER:-$SIGNER_DEFAULT}"
case "$SIGNER" in gans-master-1|gans-master-2) ;; *) fail "signer '$SIGNER' is not gans-master-1|2" ;; esac
SIG="$ARCHIVE.sig"
[ -f "$SIG" ] || fail "release is not signed: no $SIG"
command -v ssh-keygen > /dev/null || fail "ssh-keygen not found"
run ssh-keygen -Y verify -f "$LINK/allowed_signers" -I "$SIGNER" -n kambala-release -s "$SIG" < "$ARCHIVE" \
  || fail "signature NOT valid: $SIGNER against ~/kws/allowed_signers (see $LOG)"
ok "$(grep -o 'Good "kambala-release" signature.*' "$LOG" | tail -n 1)"

say "== A5. archive structure (all under $COMPONENT-$VERSION/, regular files only, release.json, one wheel)"
run "$PY" - "$ARCHIVE" "$COMPONENT" "$VERSION" << 'EOF' || fail "archive structure check failed (see $LOG)"
import json, sys, tarfile
arc, comp, ver = sys.argv[1:4]
pref = f"{comp}-{ver}"
bad, wheels, meta = [], [], None
with tarfile.open(arc, "r:gz") as t:
    for m in t.getmembers():
        n = m.name
        parts = n.split("/")
        if n.startswith("/") or ".." in parts or parts[0] != pref:
            bad.append(f"path {n}")
        if not (m.isreg() or m.isdir()):
            bad.append(f"type {n} ({'hardlink' if m.islnk() else 'symlink' if m.issym() else 'special'})")
        if n == f"{pref}/release.json":
            meta = json.load(t.extractfile(m))
        if n.startswith(f"{pref}/wheels/kambala_ws-") and n.endswith(".whl"):
            wheels.append(n.rsplit("/", 1)[1])
if meta != {"component": comp, "version": ver}:
    bad.append(f"release.json inside: {meta!r}")
if len(wheels) != 1 or not wheels[0].startswith(f"kambala_ws-{ver}-"):
    bad.append(f"kambala_ws wheels: {wheels} (need exactly one of version {ver})")
print("\n".join(bad) if bad else f"structure OK, wheel {wheels[0]}")
sys.exit(1 if bad else 0)
EOF
ok "structure, release.json and wheel match $COMPONENT $VERSION"

# ---------------------------------------------------------------- phase B: prepare, nothing live touched
PHASE="B"
say "== B1. unpack into $REL_TOP"
state_set STATUS preparing
if [ -e "$REL_TOP" ]; then
  say "   removing leftover $REL_TOP of an earlier attempt (not live: ~/kws is a directory)"
  rm -rf "$REL_TOP" || fail "cannot remove leftover $REL_TOP"
fi
mkdir -p "$REL_TOP" || fail "mkdir $REL_TOP"
run tar -xzf "$ARCHIVE" -C "$REL_TOP" --no-same-owner || fail "tar -x"
[ -f "$REL_DIR/release.json" ] && [ -d "$REL_DIR/wheels" ] && [ -d "$REL_DIR/deploy" ] || fail "unpacked tree incomplete"
# Windows-built archives carry no exec bits; ~/.bash_profile runs deploy/kambala-session-start.sh directly.
chmod +x "$REL_DIR"/deploy/*.sh || fail "chmod deploy/*.sh"
ok "$REL_DIR"

say "== B2. machine state from ~/kws (copy_machine_state + display_state.json)"
copied=""
for f in .env allowed_signers update_state.json display_node.txt display_notice.json display_state.json; do
  if [ -f "$LINK/$f" ]; then cp -p "$LINK/$f" "$REL_DIR/$f" || fail "copy $f"; copied="$copied $f"; fi
done
for f in "$LINK"/events*.jsonl; do
  [ -f "$f" ] || continue
  cp -p "$f" "$REL_DIR/" || fail "copy $(basename "$f")"; copied="$copied $(basename "$f")"
done
if [ -d "$LINK/profiles" ]; then cp -a "$LINK/profiles" "$REL_DIR/profiles" || fail "copy profiles/"; copied="$copied profiles/"; fi
for f in $copied; do
  f="${f%/}"
  if [ -d "$LINK/$f" ]; then
    diff -rq "$LINK/$f" "$REL_DIR/$f" >> "$LOG" 2>&1 || fail "copy of $f differs"
  else
    cmp -s "$LINK/$f" "$REL_DIR/$f" || fail "copy of $f differs"
  fi
done
ok "copied and compared:$copied"
[ -f "$REL_DIR/allowed_signers" ] || fail "allowed_signers did not reach the release"

say "== B3. .venv from the release wheels (--no-index)"
V_DIR="$REL_DIR/.venv"
run "$PY" -m venv "$V_DIR" || fail "python3 -m venv"
KW="$(ls "$REL_DIR"/wheels/kambala_ws-"$VERSION"-*.whl)"
DEPS=()
for w in "$REL_DIR"/wheels/*.whl; do [ "$w" = "$KW" ] || DEPS+=("$w"); done
if [ "${#DEPS[@]}" -gt 0 ]; then
  run "$V_DIR/bin/python" -m pip install --no-index --find-links "$REL_DIR/wheels" "${DEPS[@]}" || fail "pip install dependency wheels"
fi
run "$V_DIR/bin/python" -m pip install --no-index --no-deps --force-reinstall "$KW" || fail "pip install $(basename "$KW")"
out="$(import_check "$V_DIR" 2>> "$LOG")" || fail "import check in the new .venv"
ok "kambala-ws $out"

say "== B4. files the session takes from ~/kws exist in the release"
missing=""
refs_src="$(cat "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.config/labwc/autostart" "$HOME"/.config/autostart/*.desktop 2> /dev/null; crontab -l 2> /dev/null || true)"
refs="$(printf '%s\n' "$refs_src" | grep -oE '(\$\{?HOME\}?|~|'"$HOME"')/kws/[A-Za-z0-9._/-]+' | sort -u)"
for r in $refs; do
  rel="${r#*/kws/}"
  if [ ! -e "$REL_DIR/$rel" ]; then missing="$missing $rel"
  elif [[ "$rel" == *.sh ]] && [ ! -x "$REL_DIR/$rel" ]; then missing="$missing $rel(not executable)"; fi
done
[ -z "$missing" ] || fail "session files refer to ~/kws/ paths missing in the release:$missing"
ok "$(printf '%s\n' "$refs" | grep -c . ) reference(s) resolved: ${refs//$'\n'/ }"
state_set STATUS prepared

# ---------------------------------------------------------------- phase C: switch
arm_out="$(arm_check 2>&1)" || fail "rc reports ARMED - not while flying ($arm_out)"
PHASE="C"
OLD_DIR="$HOME/kws.pre-release-$STAMP"
BK="$MIG/backup-$STAMP"
say "== C1. backup of user units and labwc/pcmanfm config -> $BK"
mkdir -p "$BK" || fail "mkdir $BK"
state_set STAMP "$STAMP"
state_set VERSION "$VERSION"
state_set OLD_DIR "$OLD_DIR"
state_set BACKUP "$BK"
state_set REL_TOP "$REL_TOP"
for pair in "systemd_user:$SYSTEMD_USER" "labwc:$HOME/.config/labwc" "pcmanfm:$HOME/.config/pcmanfm"; do
  name="${pair%%:*}"; path="${pair#*:}"
  if [ -e "$path" ]; then
    cp -a "$path" "$BK/$name" || fail "backup $path"
    state_set "HAD_$name" 1
  else
    state_set "HAD_$name" 0
  fi
done
linger="$(loginctl show-user "$(id -un)" -p Linger --value 2> /dev/null || echo unknown)"
state_set LINGER_BEFORE "$linger"
ok "units, labwc, pcmanfm saved; linger was '$linger'"

say "== C2. stop old services"
state_set STATUS switching
run systemctl --user stop "${SERVICES_OLD[@]}" || fail "systemctl --user stop"
ok "${SERVICES_OLD[*]} stopped"

say "== C3. mv ~/kws -> $OLD_DIR (kept, never deleted); ~/kws -> release"
mv "$LINK" "$OLD_DIR" || fail "mv $LINK $OLD_DIR"
[ -d "$OLD_DIR" ] && [ ! -e "$LINK" ] || fail "mv result unexpected"
ln -s "$REL_DIR" "$LINK" || fail "ln -s $REL_DIR $LINK"
[ "$(readlink "$LINK")" = "$REL_DIR" ] || fail "link target wrong"
printf '%s\n' "$VERSION" > "$RELEASES/current" || fail "write $RELEASES/current"
ok "~/kws -> $REL_DIR, current=$VERSION"

say "== C4. installers of the release: ${INSTALLERS[*]}"
for s in "${INSTALLERS[@]}"; do
  # KWS_RC_RT_PRIORITY=0 / KWS_RC_SET_JSPOLL=0: install-rc.sh leaves /etc and cmdline.txt alone
  # (set on this RM earlier, KWS-010); the variables only steer the installer, not the services.
  say "   install-$s.sh"
  run env KWS_INSTALL_DIR="$HOME/kws" KWS_RC_RT_PRIORITY=0 KWS_RC_SET_JSPOLL=0 bash "$LINK/deploy/install-$s.sh" \
    || fail "deploy/install-$s.sh failed (output in $LOG)"
done
ok "5 installers done"

say "== C5. start"
run systemctl --user daemon-reload || fail "daemon-reload"
run systemctl --user restart "${SERVICES_OLD[@]}" || fail "restart ${SERVICES_OLD[*]}"
run systemctl --user restart kambala-update || fail "start kambala-update"
state_set STATUS switched

PHASE="C"
if ! verify_switched; then fail "post-switch checks failed"; fi
state_set STATUS "done"
say "=== DONE: RM on release $VERSION. Old directory: $OLD_DIR (keep until HIL passes). Log: $LOG"
exit 0
