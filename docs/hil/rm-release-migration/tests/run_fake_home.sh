#!/bin/bash
# Kambala 2026-09-29: test harness for rm_migrate.sh / rm_rollback.sh in a fake HOME on Linux.
#   tests/run_fake_home.sh <OUT>   OUT = build_release.sh output with 0.0.2, 0.0.3 and 0.0.4 (0.0.4 carries
#                                  the 0.0.3 wheel); built here when missing (needs git clones + PyPI).
# Real: bash, tar, python3.13 venv + pip (offline, --no-index), ssh-keygen (test ed25519 keys),
#       the release's own deploy/install-*.sh and kambala_ws.update (autoupdate checks).
# Stubs (tests/stubs): systemctl, loginctl, systemd-analyze, crontab, python3 -> python3.13 (+faults).
# Old layout of ~/kws is rebuilt from the live RM description (HANDOFF-cloud 2026-09-29 10:59).
set -u
set -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROC="$(dirname "$HERE")"
STUBS="$HERE/stubs"
OUT="${1:-}"
[ -n "$OUT" ] || { echo "usage: $0 <build_release.sh output dir>"; exit 2; }
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
PY313="${FAKE_PY313:-/usr/bin/python3.13}"
WS_SRC_REPO="${WS_REPO:-/home/user/kambala-workstation}"
WS_REF="${WS_REF:-8463ef9}"   # workstation release/0.0.2 (main 2e6432a without KWS-029, version 0.0.2)

[ -f "$OUT/workstation-0.0.2.tgz" ] || bash "$PROC/build_release.sh" 0.0.2 --ref "$WS_REF" --out "$OUT" > /dev/null || { echo "build 0.0.2 failed"; exit 1; }
[ -f "$OUT/workstation-0.0.3.tgz" ] || bash "$PROC/build_release.sh" 0.0.3 --ref "$WS_REF" --test-version --out "$OUT" > /dev/null || { echo "build 0.0.3 failed"; exit 1; }
[ -f "$OUT/workstation-0.0.4.tgz" ] || bash "$PROC/build_release.sh" 0.0.4 --ref "$WS_REF" --test-version --out "$OUT" --wheels-from "$OUT/wheels-0.0.3" > /dev/null || { echo "build 0.0.4 failed"; exit 1; }

T="$(mktemp -d /tmp/kws-fakehome.XXXXXX)"
echo "work dir: $T"
PASS=0; FAILN=0; RESULTS=()
ok() { PASS=$((PASS + 1)); RESULTS+=("PASS  $*"); echo "  PASS $*"; }
bad() { FAILN=$((FAILN + 1)); RESULTS+=("FAIL  $*"); echo "  FAIL $*"; }
check() { local d="$1"; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }

# ---------------------------------------------------------------- keys, signed releases, server
mkdir -p "$T/keys" "$T/srv/releases/workstation" "$T/srv/rc" "$T/srv/home" "$T/variants"
for k in master1 master2 other; do ssh-keygen -q -t ed25519 -N '' -C "test-$k" -f "$T/keys/$k"; done
sign() {  # archive key signer -> .sig, .sha256 and <name>-release.json with sig+signer
  local a="$1" key="$2" signer="$3" v; v="$(basename "$a" .tgz)"; v="${v#workstation-}"
  rm -f "$a.sig"; ssh-keygen -q -Y sign -f "$key" -n kambala-release "$a" 2> /dev/null
  sha256sum "$a" | awk '{print $1}' > "$a.sha256"
  "$PY313" - "$a" "$v" "$signer" "${a%.tgz}-release.json" << 'EOF'
import hashlib, json, sys
a, v, signer, out = sys.argv[1:5]
d = {"version": v, "date": "2026-09-29", "notes": "fake", "sha256": hashlib.sha256(open(a, "rb").read()).hexdigest(),
     "archive": a.rsplit("/", 1)[1], "sig": open(a + ".sig").read(), "signer": signer}
json.dump(d, open(out, "w"), indent=2)
EOF
}
publish() {  # version [src archive] -> fake server tree (release.json, .tgz, .sha256, .sig)
  local v="$1" src="${2:-$T/signed/workstation-$1.tgz}" d="$T/srv/releases/workstation/$1"
  rm -rf "$d"; mkdir -p "$d"
  cp "$src" "$d/workstation-$v.tgz"; cp "$src.sha256" "$d/workstation-$v.tgz.sha256"
  [ -f "$src.sig" ] && cp "$src.sig" "$d/workstation-$v.tgz.sig"
  cp "${src%.tgz}-release.json" "$d/release.json"
}
latest() {  # version [nosig] -> latest.json the way the server builds it
  "$PY313" - "$T/srv/releases/workstation/$1/release.json" "$T/srv/releases/workstation/latest.json" "${2:-}" << 'EOF'
import json, sys
m = json.load(open(sys.argv[1]))
d = {"version": m["version"], "url": f"/releases/workstation/{m['version']}/{m['archive']}", "sha256": m["sha256"], "notes": ""}
if sys.argv[3] != "nosig":
    d["sig"], d["signer"] = m["sig"], m["signer"]
json.dump(d, open(sys.argv[2], "w"))
EOF
}
mkdir -p "$T/signed"
for v in 0.0.2 0.0.3 0.0.4; do cp "$OUT/workstation-$v.tgz" "$T/signed/"; sign "$T/signed/workstation-$v.tgz" "$T/keys/master1" gans-master-1; publish "$v"; done
latest 0.0.2
echo '{"bind_state": "bound", "arm_safe": true}' > "$T/srv/rc/status"
echo '{"ok": true}' > "$T/srv/home/status"
echo '{"visible_count": 1, "last_visible": 1}' > "$T/srv/home/ui-heartbeat-state"
PORT="$("$PY313" -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
"$PY313" "$HERE/fake_server.py" "$T/srv" "$PORT" &
SRV_PID=$!
trap 'kill $SRV_PID 2> /dev/null' EXIT
sleep 1
URL="http://127.0.0.1:$PORT"

# crafted variants (all version 0.0.2, used with --archive)
mkvariant() {  # name kind
  local d="$T/variants/$1"; mkdir -p "$d"
  "$PY313" - "$T/signed/workstation-0.0.2.tgz" "$d/workstation-0.0.2.tgz" "$2" << 'EOF'
import gzip, io, sys, tarfile
src, dst, kind = sys.argv[1:4]
with tarfile.open(src, "r:gz") as t, gzip.open(dst, "wb") as gz, tarfile.open(fileobj=gz, mode="w") as out:
    for m in t.getmembers():
        data = t.extractfile(m).read() if m.isreg() else None
        if kind == "brokenwheel" and m.name.endswith("/python_dotenv-1.2.3-py3-none-any.whl"):
            data = data[: len(data) // 2]; m.size = len(data)
        out.addfile(m, io.BytesIO(data) if data is not None else None)
    if kind == "hardlink":
        h = tarfile.TarInfo("workstation-0.0.2/deploy/dup-install-common.sh")
        h.type = tarfile.LNKTYPE; h.linkname = "workstation-0.0.2/deploy/install-common.sh"
        out.addfile(h)
EOF
  sign "$d/workstation-0.0.2.tgz" "$T/keys/master1" gans-master-1
}
mkvariant hardlink hardlink
mkvariant brokenwheel brokenwheel
mkdir -p "$T/variants/othersig"; cp "$T/signed/workstation-0.0.2.tgz" "$T/variants/othersig/"
sign "$T/variants/othersig/workstation-0.0.2.tgz" "$T/keys/other" gans-master-1

# clean workstation copy for the old layout
mkdir -p "$T/wsold"; git -C "$WS_SRC_REPO" archive "$WS_REF" | tar -x -C "$T/wsold"

# ---------------------------------------------------------------- fake HOME with the old layout
new_home() {  # name -> sets H, FS
  H="$T/h-$1"; FS="$T/h-$1.state"
  rm -rf "$H" "$FS"; mkdir -p "$H" "$FS/active"
  local k="$H/kws"
  mkdir -p "$k"
  cp -a "$T/wsold/src" "$T/wsold/deploy" "$T/wsold/assets" "$T/wsold/pyproject.toml" "$k/"
  printf 'KWS_SERVER_HOST=10.66.0.1\nKWS_SERVER_RC_UDP_HOST=10.66.0.1\nKWS_SERVER_RC_UDP_PORT=5000\n' > "$k/.env"
  mkdir -p "$k/profiles/handset" "$k/profiles/aircraft"
  echo '{"id": "h1"}' > "$k/profiles/handset/h1.json"; echo '{"id": "a1"}' > "$k/profiles/aircraft/a1.json"
  echo '{"handset": "h1", "aircraft": "a1"}' > "$k/profiles/active.json"
  echo '{"ts": 1, "text": "old event"}' > "$k/events.jsonl"; echo '{"ts": 0}' > "$k/events-2026-09-28.jsonl"
  echo '{"state": "playing"}' > "$k/display_state.json"; echo hil > "$k/display_node.txt"
  printf '#!/bin/sh\necho old\n' > "$k/flight-display.sh"; chmod +x "$k/flight-display.sh"
  echo "old rc log" > "$k/rc.log"; mkdir -p "$k/hdmitest"; echo x > "$k/hdmitest/x"
  mkdir -p "$H/kws-venv/bin"; ln -s "$PY313" "$H/kws-venv/bin/python"
  local u="$H/.config/systemd/user"; mkdir -p "$u/default.target.wants"
  for s in rc home display ui; do
    printf '[Unit]\nDescription=old kambala-%s\n\n[Service]\nType=simple\nEnvironment=PYTHONPATH=%%h/kws/src\nEnvironmentFile=-%%h/kws/.env\nWorkingDirectory=%%h/kws\nExecStart=%%h/kws-venv/bin/python -m kambala_ws.%s\nRestart=always\n\n[Install]\nWantedBy=default.target\n' "$s" "$s" > "$u/kambala-$s.service"
    ln -s "$u/kambala-$s.service" "$u/default.target.wants/kambala-$s.service"
    touch "$FS/active/kambala-$s.service"
  done
  cp "$T/wsold/deploy/kambala-session.target" "$u/"
  touch "$FS/linger"
  mkdir -p "$H/.config/labwc"
  PYTHONPATH="$T/wsold/src" "$PY313" -c 'import sys; from kambala_ws.sysprep import render_labwc_autostart as a, render_bash_profile_block as b; open(sys.argv[2],"w").write(a(sys.argv[1])); open(sys.argv[3],"w").write("# old profile\n" + b(sys.argv[1]))' \
    "$H/kws" "$H/.config/labwc/autostart" "$H/.bash_profile"
  printf '<?xml version="1.0"?>\n<labwc_config>\n  <windowRules>\n    <windowRule identifier="kambala-flight"/>\n  </windowRules>\n</labwc_config>\n' > "$H/.config/labwc/rc.xml"
  mkdir -p "$H/kws-migration"
  cp "$PROC/rm_migrate.sh" "$PROC/rm_rollback.sh" "$H/kws-migration/"
  cp "$T/keys/master1.pub" "$H/kws-migration/id_kambala_master_1.pub"
  cp "$T/keys/master2.pub" "$H/kws-migration/id_kambala_master_2.pub"
  snapshot > "$H.snap0"
}
snapshot() {  # everything the migration may touch, except its own logs in ~/.kws-migration
  (cd "$H" && {
    find kws kws-venv .config .bash_profile -printf '%y %m %p -> %l\n' 2> /dev/null | sort
    find kws kws-venv .config .bash_profile -type f -exec sha256sum {} + 2> /dev/null | sort -k2
    ls -d kws* 2> /dev/null
  })
  ls "$FS/active" 2> /dev/null | sed 's/^/active: /'
  [ -e "$FS/linger" ] && echo "linger: yes"
}
envrun() {  # run a command inside the fake HOME with the stubs
  env HOME="$H" PATH="$STUBS:$PATH" FAKE_STATE="$FS" FAKE_PY313="$PY313" KWS_MIGRATE_ALLOW_ROOT=1 \
    KWS_MIGRATE_SERVER_URL="$URL" KWS_MIGRATE_RC_STATUS_URL="${RCURL:-$URL/rc/status}" KWS_MIGRATE_ACTIVE_TIMEOUT=6 "$@"
}
migrate() {  # args... ; rc in MRC, output in $H.out
  (cd "$H" && envrun setsid -w bash "$H/kws-migration/rm_migrate.sh" "$@") > "$H.out" 2>&1; MRC=$?
  cat "$H.out" >> "$T/all.log"
}
# shellcheck disable=SC2120
rollback() {
  (cd "$H" && envrun setsid -w bash "$H/kws-migration/rm_rollback.sh" "$@") > "$H.rb" 2>&1; RRC=$?
  cat "$H.rb" >> "$T/all.log"
}
same_as_orig() { snapshot > "$H.snapN"; diff -u "$H.snap0" "$H.snapN" > "$H.diff"; }
only_signers_added() {  # intended changes of phases A/B: ~/kws/allowed_signers, a prepared ~/kws-releases
  snapshot > "$H.snapN"
  diff "$H.snap0" "$H.snapN" | grep '^[<>]' | grep -v -e ' kws/allowed_signers' -e '^> kws-releases$' > "$H.diff"; [ ! -s "$H.diff" ]
}
no_stop_calls() { ! grep -q 'systemctl --user stop' "$FS/calls.log" 2> /dev/null; }
is_link_to() { [ -L "$H/kws" ] && [ "$(readlink -f "$H/kws")" = "$(readlink -f "$H/kws-releases/$1/workstation-$1")" ]; }
venv_version() { "$H/kws/.venv/bin/python" -I -c 'import importlib.metadata as m, kambala_ws, pathlib; print(m.version("kambala-ws"), pathlib.Path(kambala_ws.__file__).resolve())'; }
update_once() {  # the real kambala_ws.update of the active release, against the fake server
  (cd "$H/kws" && envrun KWS_UPDATE_SERVER_URL="$URL" KWS_UPDATE_RC_STATUS_URL="$URL/rc/status" \
    KWS_UPDATE_HOME_STATUS_URL="$URL/home/status" KWS_UPDATE_KIOSK_HB_URL="$URL/home/ui-heartbeat-state" \
    KWS_UPDATE_VERIFY_TIMEOUT_S=10 "$H/kws/.venv/bin/python" -m kambala_ws.update --once) > "$H.upd" 2>&1; URC=$?
  cat "$H.upd" >> "$T/all.log"
}
downloads() { awk -v p="/$1/" 'index($0, p) {n++} END {print n + 0}' "$T/srv/downloads.log" 2> /dev/null || echo 0; }

echo "== S1 happy path, repeat run, autoupdate (KWS-022/028/030), rollback, re-migration"
new_home main
migrate 0.0.2
check "S1 migrate 0.0.2: exit 0" [ "$MRC" = 0 ]
check "S1 ~/kws -> ~/kws-releases/0.0.2/workstation-0.0.2" is_link_to 0.0.2
check "S1 old dir kept as ~/kws.pre-release-*" bash -c "ls -d '$H'/kws.pre-release-* > /dev/null"
old="$(ls -d "$H"/kws.pre-release-* | head -n 1)"
check "S1 old dir content unchanged (+allowed_signers)" bash -c "cd '$old' && [ -f rc.log ] && [ -x flight-display.sh ] && cmp -s .env '$H/kws/.env' && [ -f allowed_signers ]"
check "S1 machine state copied (.env events* display_* profiles allowed_signers)" bash -c "cd '$H/kws' && cmp -s .env '$old/.env' && cmp -s events.jsonl '$old/events.jsonl' && cmp -s events-2026-09-28.jsonl '$old/events-2026-09-28.jsonl' && cmp -s display_state.json '$old/display_state.json' && cmp -s display_node.txt '$old/display_node.txt' && diff -rq profiles '$old/profiles' && [ \"\$(stat -c %a allowed_signers)\" = 644 ] && [ \$(wc -l < allowed_signers) = 2 ]"
check "S1 no old junk in the release (rc.log, flight-display.sh, hdmitest)" bash -c "cd '$H/kws' && [ ! -e rc.log ] && [ ! -e flight-display.sh ] && [ ! -e hdmitest ]"
check "S1 .venv imports kambala-ws 0.0.2 from the release .venv" bash -c "$(declare -f venv_version); H='$H'; venv_version | grep -q '^0.0.2 $H/kws-releases/0.0.2/workstation-0.0.2/.venv/'"
check "S1 5 units: %h/kws/.venv, no PYTHONPATH, enabled" bash -c "cd '$H/.config/systemd/user' && for s in rc home display ui update; do grep -q '^ExecStart=%h/kws/.venv/bin/python -m kambala_ws' kambala-\$s.service && ! grep -q PYTHONPATH kambala-\$s.service && [ -L default.target.wants/kambala-\$s.service ] || exit 1; done"
check "S1 5 services active" bash -c "cd '$FS/active' && ls kambala-rc.service kambala-home.service kambala-display.service kambala-ui.service kambala-update.service > /dev/null"
check "S1 kambala-session-start.sh executable via ~/kws" [ -x "$H/kws/deploy/kambala-session-start.sh" ]
check "S1 current=0.0.2" [ "$(cat "$H/kws-releases/current")" = 0.0.2 ]
snapshot > "$H.snapM"
migrate 0.0.2
snapshot > "$H.snapM2"
check "S2 repeat run: exit 0, 'ALREADY MIGRATED'" bash -c "[ $MRC = 0 ] && grep -q 'ALREADY MIGRATED, all checks OK' '$H.out'"
check "S2 repeat run changed nothing" cmp -s "$H.snapM" "$H.snapM2"

echo "== S3 autoupdate with the real kambala_ws.update (after migration)"
# (a) tampered archive: sha256 of latest.json matches the file, signature does not -> refused, remembered
cp "$T/signed/workstation-0.0.3.tgz" "$T/tampered.tgz"; printf 'X' >> "$T/tampered.tgz"
d="$T/srv/releases/workstation/0.0.3"; cp "$T/tampered.tgz" "$d/workstation-0.0.3.tgz"
"$PY313" -c 'import hashlib,json,sys; p=sys.argv[1]; m=json.load(open(p)); m["sha256"]=hashlib.sha256(open(sys.argv[2],"rb").read()).hexdigest(); json.dump(m,open(p,"w"))' "$d/release.json" "$T/tampered.tgz"
latest 0.0.3
: > "$T/srv/downloads.log"
update_once; u1=$URC; update_once; update_once
check "S3a tampered 0.0.3: refused (verifying), 3 cycles -> 1 download, ~/kws still 0.0.2" bash -c "[ $u1 != 0 ] && grep -q 'підпис недійсний\|уже відхилено' '$H.upd' && [ $(downloads 0.0.3) = 1 ] && [ \"\$(readlink -f '$H/kws')\" = '$H/kws-releases/0.0.2/workstation-0.0.2' ] && [ ! -e '$H/kws-releases/0.0.3' ]"
# (b) unsigned: the same archive without sig -> refused once, then remembered
publish 0.0.3; latest 0.0.3 nosig; : > "$T/srv/downloads.log"
update_once; u1=$URC; update_once
check "S3b unsigned 0.0.3: refused, 2 cycles -> 1 download, version unchanged" bash -c "[ $u1 != 0 ] && [ $(downloads 0.0.3) = 1 ] && is=\$(readlink -f '$H/kws') && [ \"\$is\" = '$H/kws-releases/0.0.2/workstation-0.0.2' ]"
# (c) signed, but ~/kws/allowed_signers missing -> refused; file back -> new attempt -> installed
latest 0.0.3; mv "$H/kws/allowed_signers" "$T/as.saved"; : > "$T/srv/downloads.log"
update_once; u1=$URC; update_once; n1=$(downloads 0.0.3)
mv "$T/as.saved" "$H/kws/allowed_signers"
update_once; u3=$URC
check "S3c no allowed_signers: refused, 1 download for 2 cycles" bash -c "[ $u1 != 0 ] && [ $n1 = 1 ]"
check "S3c allowed_signers back -> new attempt -> updated to 0.0.3" bash -c "[ $u3 = 0 ] && [ $(downloads 0.0.3) = 2 ] && [ \"\$(readlink -f '$H/kws')\" = '$H/kws-releases/0.0.3/workstation-0.0.3' ]"
check "S3c 0.0.3 .venv version, 0.0.2 kept for rollback, state files carried" bash -c "$(declare -f venv_version); H='$H'; venv_version | grep -q '^0.0.3 ' && [ -d '$H/kws-releases/0.0.2/workstation-0.0.2/.venv' ] && [ -f '$H/kws/allowed_signers' ] && cmp -s '$H/kws/.env' '$old/.env'"
check "S3c deploy/kambala-session-start.sh executable after autoupdate (Linux-built archive)" [ -x "$H/kws/deploy/kambala-session-start.sh" ]
# (d) negative KWS-030: 0.0.4 carries the 0.0.3 wheel -> refused before the switch
latest 0.0.4; update_once
check "S3d 0.0.4 with wheel 0.0.3: refused ('Версія колеса'), ~/kws still 0.0.3, no 0.0.4 dir" bash -c "[ $URC != 0 ] && grep -q 'Версія колеса' '$H.upd' && [ \"\$(readlink -f '$H/kws')\" = '$H/kws-releases/0.0.3/workstation-0.0.3' ] && [ ! -e '$H/kws-releases/0.0.4' ]"
latest 0.0.2

echo "== S4 rollback after migration + autoupdate; repeat rollback; re-migration"
rollback
check "S4 rollback: exit 0" [ "$RRC" = 0 ]
check "S4 old ~/kws, old units, labwc, services, linger exactly as before" same_as_orig
check "S4 kambala-update not active, ~/kws-releases moved aside" bash -c "[ ! -e '$FS/active/kambala-update.service' ] && [ ! -e '$H/kws-releases' ] && ls -d '$H'/.kws-migration/kws-releases.rolled-back-* > /dev/null"
rollback
check "S4 repeat rollback: exit 0, 'already rolled back', nothing changed" bash -c "[ $RRC = 0 ] && grep -q 'already rolled back' '$H.rb'"
check "S4 repeat rollback left state identical" same_as_orig
migrate 0.0.2
check "S4 re-migration after rollback: exit 0, link 0.0.2" bash -c "[ $MRC = 0 ] && [ \"\$(readlink -f '$H/kws')\" = '$H/kws-releases/0.0.2/workstation-0.0.2' ]"
rollback
check "S4 second rollback restores the original again" bash -c "[ $RRC = 0 ]"
check "S4 state after second rollback" same_as_orig

echo "== F: failures in phases A/B (nothing live touched; rollback undoes allowed_signers)"
fail_prepare() {  # label, expected text, migrate args...
  local label="$1" want="$2"; shift 2
  migrate "$@"
  check "$label: exit 1 + '$want'" bash -c "[ $MRC = 1 ] && grep -q -- '$want' '$H.out'"
  check "$label: live untouched (no stop, same units/dir; only ~/kws/allowed_signers added)" bash -c "$(declare -f no_stop_calls); FS='$FS'; no_stop_calls && [ -d '$H/kws' ] && [ ! -L '$H/kws' ] && ! ls -d '$H'/kws.pre-release-* > /dev/null 2>&1"
  check "$label: diff vs original = only allowed_signers (+ prepared ~/kws-releases)" only_signers_added
  rollback
  check "$label: rm_rollback.sh -> exactly the original" bash -c "[ $RRC = 0 ]"
  check "$label: state after rollback" same_as_orig
}
new_home f404;  fail_prepare "F1 version not on server" "download from" 0.0.9
new_home fsha;  cp "$T/tampered.tgz" "$T/variants/tampered-0.0.2.tgz" 2> /dev/null
mkdir -p "$T/variants/sha"; cp "$T/signed/workstation-0.0.2.tgz" "$T/variants/sha/"; cp "$T/signed/workstation-0.0.2-release.json" "$T/signed/workstation-0.0.2.tgz.sig" "$T/variants/sha/"
printf 'X' >> "$T/variants/sha/workstation-0.0.2.tgz"; cp "$T/variants/sha/workstation-0.0.2-release.json" "$T/variants/sha/release.json"
fail_prepare "F2 sha256 mismatch" "sha256 mismatch" 0.0.2 --archive "$T/variants/sha/workstation-0.0.2.tgz"
new_home fsig;  fail_prepare "F3 signature by an untrusted key" "signature NOT valid" 0.0.2 --archive "$T/variants/othersig/workstation-0.0.2.tgz"
new_home fpub;  rm "$H/kws-migration/id_kambala_master_2.pub"; snapshot > "$H.snap0"
migrate 0.0.2
check "F4 missing public key #2: exit 1, nothing changed at all" bash -c "[ $MRC = 1 ] && grep -q 'id_kambala_master_2.pub not found' '$H.out'"
check "F4 state identical (allowed_signers not written)" same_as_orig
new_home fhard; fail_prepare "F5 hard-link entry in the archive" "archive structure check failed" 0.0.2 --archive "$T/variants/hardlink/workstation-0.0.2.tgz"
cat "$H"/.kws-migration/migrate-*.log | grep -q 'type workstation-0.0.2/deploy/dup-install-common.sh (hardlink)' && ok "F5 log names the hardlink entry" || bad "F5 log names the hardlink entry"
new_home fwhl; fail_prepare "F6 release 0.0.4 carrying the 0.0.3 wheel" "archive structure check failed" 0.0.4
new_home fvenv; FAKE_VENV_FAIL=1; export FAKE_VENV_FAIL
fail_prepare "F7 python3 -m venv fails" "python3 -m venv" 0.0.2
unset FAKE_VENV_FAIL
new_home fpip; fail_prepare "F8 pip install of a broken wheel fails" "pip install dependency wheels" 0.0.2 --archive "$T/variants/brokenwheel/workstation-0.0.2.tgz"
new_home fref; echo "$H/kws/flight-display.sh &" >> "$H/.config/labwc/autostart"; snapshot > "$H.snap0"
fail_prepare "F9 labwc autostart uses ~/kws/flight-display.sh (not in the release)" "missing in the release: flight-display.sh" 0.0.2
new_home farm; echo '{"arm_safe": false}' > "$T/srv/rc/armed"; RCURL="$URL/rc/armed"
migrate 0.0.2
check "F10 ARMED: exit 1, nothing changed at all" bash -c "[ $MRC = 1 ] && grep -q 'ARMED' '$H.out'"
check "F10 state identical" same_as_orig
unset RCURL
new_home fenv; rm "$H/kws/.env"; snapshot > "$H.snap0"
migrate 0.0.2
check "F11 no ~/kws/.env: exit 1, nothing changed" bash -c "[ $MRC = 1 ] && grep -q '.env not found' '$H.out'"
check "F11 state identical" same_as_orig
new_home fretry; FAKE_VENV_FAIL=1; export FAKE_VENV_FAIL; migrate 0.0.2; r1=$MRC; unset FAKE_VENV_FAIL
migrate 0.0.2
check "F12 failed preparation, then a plain re-run succeeds" bash -c "[ $r1 = 1 ] && [ $MRC = 0 ] && [ \"\$(readlink -f '$H/kws')\" = '$H/kws-releases/0.0.2/workstation-0.0.2' ]"
rollback
check "F12 rollback -> original" same_as_orig

new_home fnone; rollback
check "F13 rm_rollback.sh on an untouched machine: exit 0, nothing changed" bash -c "[ $RRC = 0 ] && grep -q 'nothing to do' '$H.rb'"
check "F13 state identical" same_as_orig

echo "== C: failures in phase C (switch) -> automatic rollback to exactly the original"
fail_switch() {  # label, expected text
  local label="$1" want="$2"
  migrate 0.0.2
  check "$label: exit 1 + '$want' + automatic rollback OK" bash -c "[ $MRC = 1 ] && grep -q -- '$want' '$H.out' && grep -q 'rollback OK' '$H.out'"
  check "$label: exactly the original (dir, units, labwc, pcmanfm, 4 old active, linger)" same_as_orig
}
new_home cupd; export FAKE_SYSTEMCTL_FAIL="enable:kambala-update.service reenable:kambala-update.service"
fail_switch "C1 install-update.sh fails (enable)" "install-update.sh failed"; unset FAKE_SYSTEMCTL_FAIL
new_home clin; export FAKE_LOGINCTL_FAIL=1
fail_switch "C2 loginctl enable-linger fails" "install-display.sh failed"; unset FAKE_LOGINCTL_FAIL
new_home cver; export FAKE_VERIFY_FAIL=1
fail_switch "C3 systemd-analyze --user verify fails" "post-switch checks failed"; unset FAKE_VERIFY_FAIL
new_home cina; export FAKE_INACTIVE="kambala-ui"
fail_switch "C4 kambala-ui never becomes active" "not active after"; unset FAKE_INACTIVE
new_home crel; export FAKE_SYSTEMCTL_FAIL_ONCE=daemon-reload
fail_switch "C5 daemon-reload fails once" "install-display.sh failed"; unset FAKE_SYSTEMCTL_FAIL_ONCE
new_home cman; export FAKE_INACTIVE="kambala-home"
migrate 0.0.2 --no-auto-rollback; unset FAKE_INACTIVE
check "C6 --no-auto-rollback: exit 1, left switched" bash -c "[ $MRC = 1 ] && [ -L '$H/kws' ] && ls -d '$H'/kws.pre-release-* > /dev/null"
rollback
check "C6 manual rm_rollback.sh -> exactly the original" bash -c "[ $RRC = 0 ]"
check "C6 state" same_as_orig
new_home ckil; export FAKE_KILL_ON=daemon-reload
migrate 0.0.2; unset FAKE_KILL_ON
check "C7 script killed mid-switch (SSH lost / power): state 'switching', old dir kept" bash -c "grep -q '^STATUS=switching' '$H/.kws-migration/state' && ls -d '$H'/kws.pre-release-* > /dev/null && [ -f \"\$(ls -d '$H'/kws.pre-release-* | head -n 1)/.env\" ]"
migrate 0.0.2
check "C7 re-run refuses to guess (exit 1, 'already a link')" bash -c "[ $MRC = 1 ] && grep -q 'already a link' '$H.out'"
rollback
check "C7 rm_rollback.sh after the kill -> exactly the original" bash -c "[ $RRC = 0 ]"
check "C7 state" same_as_orig

echo
echo "================ SUMMARY: $PASS passed, $FAILN failed (work dir $T, full log $T/all.log)"
for r in "${RESULTS[@]}"; do echo "$r"; done
[ "$FAILN" = 0 ]
