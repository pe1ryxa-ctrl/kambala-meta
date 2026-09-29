#!/bin/bash
# Kambala 2026-09-29, HIL KWS-022/030: publish the signed workstation release <v> on the VPS
# (same steps as docs/hil/hil017_server.sh): files into the releases volume, owner 10001:999,
# POST /releases/workstation/recommend over loopback, check latest.json and the served archive.
# Run as root on the VPS:  bash vps_publish_ws.sh <version> [source dir, default /tmp/kws-rel] [--no-recommend]
#   --no-recommend  only put the files into the volume (HIL: releases recommended later, one at a time)
# The source dir holds what pc_build_release.ps1 produced:
#   workstation-<v>.tgz  workstation-<v>.tgz.sha256  workstation-<v>.tgz.sig  workstation-<v>-release.json
# A version already in the volume with the SAME sha256 is left as is (repeat run is safe);
# with another sha256 the script stops (a published release is never overwritten).
set -u
set -o pipefail
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
NOREC=0
ARGS=()
for a in "$@"; do if [ "$a" = --no-recommend ]; then NOREC=1; else ARGS+=("$a"); fi; done
V="${ARGS[0]:-}"
SRC="${ARGS[1]:-/tmp/kws-rel}"
C="workstation"
SIGNERS="${KSRV_ALLOWED_SIGNERS_HOST:-/opt/kambala/allowed_signers.d/allowed_signers}"
API="http://127.0.0.1:8003"
fail() { echo "FAIL: $*"; exit 1; }
printf '%s' "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "usage: $0 <version N.N.N> [source dir]"
A="$SRC/$C-$V.tgz"
for f in "$A" "$A.sha256" "$A.sig" "$SRC/$C-$V-release.json"; do [ -f "$f" ] || fail "missing $f"; done

echo "== 1. local checks of $A"
SHA="$(sha256sum "$A" | awk '{print $1}')"
[ "$SHA" = "$(awk '{print $1; exit}' "$A.sha256")" ] || fail "sha256 differs from $A.sha256"
python3 - "$SRC/$C-$V-release.json" "$V" "$SHA" "$C-$V.tgz" << 'EOF' || fail "release.json check"
import json, sys
p, v, sha, arc = sys.argv[1:5]
d = json.load(open(p, encoding="utf-8"))
errs = [k for k, want in (("version", v), ("sha256", sha), ("archive", arc)) if d.get(k) != want]
if not d.get("sig") or not d.get("signer"):
    errs.append("sig/signer missing - the release is unsigned (recommend would be refused)")
print("release.json:", {k: d.get(k) for k in ("version", "sha256", "archive", "signer")}, "sig:", bool(d.get("sig")))
if errs:
    print("bad fields:", errs); sys.exit(1)
EOF
SIGNER="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["signer"])' "$SRC/$C-$V-release.json")"
[ "$SIGNER" = gans-master-1 ] || [ "$SIGNER" = gans-master-2 ] || fail "signer '$SIGNER' is not gans-master-1|2"
if [ -f "$SIGNERS" ]; then
  ssh-keygen -Y verify -f "$SIGNERS" -I "$SIGNER" -n kambala-release -s "$A.sig" < "$A" || fail "signature NOT valid against $SIGNERS"
else
  echo "   note: $SIGNERS not found - signature is checked by the server at recommend"
fi
tar -tzf "$A" | grep -qv "^$C-$V/" && fail "archive has entries outside $C-$V/"
tar -tvzf "$A" | grep -q '^h' && fail "archive has hard-link entries"
[ "$(tar -xzOf "$A" "$C-$V/release.json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("component"), d.get("version"))')" = "$C $V" ] \
  || fail "$C-$V/release.json inside the archive does not name $C $V"
echo "   OK: sha256 $SHA, signer $SIGNER, structure"

echo "== 2. releases volume"
VOL="$(docker volume inspect kambala_releases_data --format '{{.Mountpoint}}')" || fail "docker volume inspect"
D="$VOL/$C/$V"
echo "   before: latest.json = $(curl -s -m 5 "$API/releases/$C/latest.json" | head -c 200)"
if [ -f "$VOL/$C/recommended.json" ]; then
  cp -p "$VOL/$C/recommended.json" "/root/kws-rel-recommended.json.before-$V"
  echo "   saved $VOL/$C/recommended.json -> /root/kws-rel-recommended.json.before-$V (for rollback)"
fi
if [ -f "$D/$C-$V.tgz" ]; then
  OLD="$(sha256sum "$D/$C-$V.tgz" | awk '{print $1}')"
  [ "$OLD" = "$SHA" ] || fail "$D already holds another $C-$V.tgz (sha256 $OLD) - not overwriting; bump the version"
  echo "   $D already holds this archive - files kept"
else
  mkdir -p "$D"
  cp "$A" "$A.sha256" "$A.sig" "$D/"
  cp "$SRC/$C-$V-release.json" "$D/release.json"
fi
chown -R 10001:999 "$VOL/$C"
ls -ln "$D"

if [ "$NOREC" = 1 ]; then
  GOT="$(curl -s -m 60 "$API/releases/$C/$V/$C-$V.tgz" | sha256sum | awk '{print $1}')"
  [ "$GOT" = "$SHA" ] || fail "served archive sha256 $GOT != $SHA"
  echo "== DONE: $C $V in the volume and served (sha256 OK), NOT recommended (--no-recommend)"
  exit 0
fi
echo "== 3. recommend $V"
R="$(curl -s -m 30 -w '\nHTTP %{http_code}' -X POST "$API/releases/$C/recommend" -H 'Content-Type: application/json' \
  -d "{\"version\":\"$V\",\"confirm\":true,\"reason\":\"HIL KWS-022/030: RM release layout $V\"}")"
echo "$R"
echo "$R" | tail -n 1 | grep -q 'HTTP 200' || fail "recommend refused"

echo "== 4. what the RM will see"
L="$(curl -s -m 5 "$API/releases/$C/latest.json")"
echo "$L" | head -c 300; echo
echo "$L" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['version']=='$V' and d['sha256']=='$SHA' and d.get('sig') and d.get('signer'), d" \
  || fail "latest.json does not carry $V / sha256 / sig / signer"
GOT="$(curl -s -m 60 "$API/releases/$C/$V/$C-$V.tgz" | sha256sum | awk '{print $1}')"
[ "$GOT" = "$SHA" ] || fail "served archive sha256 $GOT != $SHA"
echo "   OK: latest.json = $V, served archive sha256 matches"
echo "== releases log"
docker logs --since 3m releases 2>&1 | grep -i -E "recommend|signature|$C" | tail -6
echo "== DONE: $C $V recommended"
