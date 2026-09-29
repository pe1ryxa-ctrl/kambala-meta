#!/bin/bash
# Kambala 2026-09-29, HIL KWS-022/030: reproducible UNSIGNED build of the workstation release on Linux
# (cloud check / Git Bash). The signed build for the server is made on Gans's PC by pc_build_release.ps1
# with the same steps. Project code is not changed. Code: workstation branch release/0.0.2 (= main 2e6432a
# without KWS-029, version 0.0.2 committed). The release version must equal [project] version of REF;
# only HIL test releases (0.0.3+) patch it, in the throw-away copy, and only with --test-version.
#
#   build_release.sh <version> [--ws-repo DIR] [--server-repo DIR] [--ref REF (default 8463ef9)] [--out DIR]
#                    [--wheels-from DIR] [--test-version] [--python PY]
#
#   --test-version     HIL test release: <version> differs from the committed one -> patch it in the copy.
#   --wheels-from DIR  take ready wheels from DIR instead of building them (negative HIL case:
#                      release <v> that carries a kambala_ws wheel of another version).
#   --break-home-unit  HIL KWS-022 rollback case: deploy/kambala-home.service of the build copy starts a
#                      module that does not exist, so after the switch home never answers /status.
# Result in --out: workstation-<v>.tgz, .tgz.sha256, workstation-<v>-release.json, wheels-<v>/.
set -u
set -o pipefail
umask 022

V=""
WS_REPO="${WS_REPO:-/home/user/kambala-workstation}"
SRV_REPO="${SRV_REPO:-/home/user/kambala-server}"
REF="8463ef9"   # workstation release/0.0.2: main 2e6432a - KWS-029 (revert 04b165c) + version 0.0.2
OUT="$PWD/out"
WHEELS_FROM=""
BREAK_HOME=0
TEST_VERSION=0
PY="${PYTHON:-python3.13}"
COMPONENT="workstation"

die() { echo "FAIL: $*" >&2; exit 1; }
while [ $# -gt 0 ]; do
  case "$1" in
    --ws-repo) WS_REPO="$2"; shift 2 ;;
    --server-repo) SRV_REPO="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --wheels-from) WHEELS_FROM="$2"; shift 2 ;;
    --break-home-unit) BREAK_HOME=1; shift ;;
    --test-version) TEST_VERSION=1; shift ;;
    --python) PY="$2"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    -*) die "unknown option $1" ;;
    *) [ -z "$V" ] || die "extra argument $1"; V="$1"; shift ;;
  esac
done
[ -n "$V" ] || die "usage: $0 <version> [options]"
printf '%s' "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || die "version '$V' must be N.N.N (PEP 440 normal form, see README)"
command -v "$PY" > /dev/null || die "python '$PY' not found"
mkdir -p "$OUT" || die "cannot create $OUT"
OUT="$(cd "$OUT" && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SRC="$WORK/ws"; SRVSRC="$WORK/srv"; WHL="$OUT/wheels-$V"
mkdir -p "$SRC" "$SRVSRC"

echo "== 1. clean copies (git archive: no untracked files, no hard links)"
git -C "$WS_REPO" archive "$REF" | tar -x -C "$SRC" || die "git archive $WS_REPO $REF"
git -C "$SRV_REPO" archive origin/main | tar -x -C "$SRVSRC" || die "git archive $SRV_REPO origin/main"
echo "   workstation $(git -C "$WS_REPO" rev-parse --short "$REF"), server $(git -C "$SRV_REPO" rev-parse --short origin/main)"

echo "== 2. version $V"
CUR="$("$PY" -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1],"rb"))["project"]["version"])' "$SRC/pyproject.toml")" || die "pyproject.toml unreadable"
if [ "$CUR" = "$V" ]; then
  echo "   pyproject.toml at $REF: version = \"$CUR\" (committed)"
elif [ "$TEST_VERSION" != 1 ]; then
  die "pyproject.toml at $REF says $CUR, not $V. A real release is built only from a commit with that version (--test-version is for HIL test releases 0.0.3+)"
else
  echo "   HIL test release: pyproject.toml says $CUR; patched to $V in the throw-away copy only (--test-version)"
  sed -i "s/^version = \"$CUR\"\$/version = \"$V\"/" "$SRC/pyproject.toml"
  grep -q "^version = \"$V\"\$" "$SRC/pyproject.toml" || die "version patch failed"
fi

if [ "$BREAK_HOME" = 1 ]; then
  sed -i 's/-m kambala_ws\.home$/-m kambala_ws.home_hil_broken/' "$SRC/deploy/kambala-home.service"
  grep -q 'kambala_ws.home_hil_broken' "$SRC/deploy/kambala-home.service" || die "break-home-unit patch failed"
  echo "   HIL: deploy/kambala-home.service now starts kambala_ws.home_hil_broken (health check must fail -> rollback)"
fi
echo "== 3. wheels (linux aarch64, CPython 3.13)"
rm -rf "$WHL"
if [ -n "$WHEELS_FROM" ]; then
  mkdir -p "$WHL" && cp "$WHEELS_FROM"/*.whl "$WHL/" || die "copy wheels from $WHEELS_FROM"
  echo "   wheels taken from $WHEELS_FROM (negative case: wheel version may differ from $V)"
else
  PYTHON="$PY" bash "$SRC/deploy/build-wheels.sh" -o "$WHL" > "$WORK/wheels.log" 2>&1 || { cat "$WORK/wheels.log"; die "build-wheels.sh"; }
  grep -E '\.whl +\|' "$WORK/wheels.log"
fi

echo "== 4. release.py build (unsigned)"
rm -f "$OUT/$COMPONENT-$V.tgz" "$OUT/$COMPONENT-$V.tgz.sha256" "$OUT/$COMPONENT-$V.tgz.sig" "$OUT/$COMPONENT-$V-release.json"
PYTHONPATH="$SRVSRC/src" "$PY" "$SRVSRC/tools/release.py" build "$COMPONENT" "$V" --source "$SRC" \
  --wheels-dir "$WHL" --output-dir "$OUT" --notes "HIL KWS-022/030: RM release layout" > "$WORK/build.log" 2>&1 \
  || { cat "$WORK/build.log"; die "release.py build"; }
grep -E 'SHA-256|Archive +:.*bytes' "$WORK/build.log"

echo "== 5. content checks"
A="$OUT/$COMPONENT-$V.tgz"
tar -tvzf "$A" > "$WORK/list.txt" || die "tar -tvzf"
if grep -Eq '^[^-]' "$WORK/list.txt"; then
  grep -E '^[^-]' "$WORK/list.txt" | head
  die "archive has non-regular entries (hard links / symlinks / dirs); KWS-028 RM refuses hard links"
fi
echo "   entries: $(wc -l < "$WORK/list.txt"), all regular files (no hard links)"
tar -tzf "$A" | grep -v "^$COMPONENT-$V/" && die "entries outside $COMPONENT-$V/"
tar -xzOf "$A" "$COMPONENT-$V/release.json" | "$PY" -c "import json,sys; d=json.load(sys.stdin); assert d=={'component':'$COMPONENT','version':'$V'}, d; print('   release.json inside:', d)" || die "release.json inside"
N="$(tar -tzf "$A" | grep -c "^$COMPONENT-$V/wheels/kambala_ws-")"
[ "$N" = 1 ] || die "expected one kambala_ws wheel, found $N"
KW="$(tar -tzf "$A" | grep "^$COMPONENT-$V/wheels/kambala_ws-")"
case "$KW" in *"/kambala_ws-$V-"*) echo "   wheel: ${KW##*/}" ;; *) echo "   WARNING: wheel ${KW##*/} is NOT of version $V (expected only for the negative case)" ;; esac
tar -tvzf "$A" | grep -E ' [^ ]+/deploy/kambala-session-start\.sh$' | grep -q '^-rwx' || die "deploy/kambala-session-start.sh is not executable in the archive"
# *.sh: the x bit in the archive must be exactly the git mode at REF (100755 <-> -rwx). Only the scripts
# that are started directly (session start from ~/.bash_profile, install-kiosk.sh) are 100755 in git; the
# rest are run as "bash <script>" and are 100644 there. A Windows build loses the x bit (README finding 6).
git -C "$WS_REPO" ls-tree -r "$REF" | awk '$4 ~ /\.sh$/ {print ($1 == "100755" ? "x" : "-"), $4}' | sort > "$WORK/sh.git"
awk -v p="$COMPONENT-$V/" '$NF ~ /\.sh$/ {n = $NF; sub("^" p, "", n); print (substr($1, 4, 1) == "x" ? "x" : "-"), n}' "$WORK/list.txt" | sort > "$WORK/sh.tar"
diff "$WORK/sh.git" "$WORK/sh.tar" > /dev/null || { diff "$WORK/sh.git" "$WORK/sh.tar"; die "*.sh x bits in the archive differ from git ($REF)"; }
echo "   *.sh: $(wc -l < "$WORK/sh.tar") files, x bits = git: +x $(awk '$1 == "x" {printf "%s ", $2}' "$WORK/sh.tar")"
if grep -Eq "/assets/bf/|/kambala_ws/home/fc\.py$" "$WORK/list.txt"; then
  die "KWS-029 files (assets/bf/, home/fc.py) in the archive: build from release/0.0.2, not main"
fi
echo "== wheels sha256"
(cd "$WHL" && sha256sum ./*.whl)
echo "== DONE: $A"
cat "$A.sha256"
