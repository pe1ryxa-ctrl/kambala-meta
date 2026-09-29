#!/bin/bash
# shellcheck disable=SC2088  # "~/kws" in messages is text for the operator, not a path
# Kambala 2026-09-29, HIL KWS-022/030: undo rm_migrate.sh on the operator workstation (user gans).
# Returns the old plain directory ~/kws (from ~/kws.pre-release-<stamp>), the old user units and the
# labwc/pcmanfm config saved by rm_migrate.sh, switches kambala-update off, starts the 4 old services.
# ~/kws/allowed_signers (first step of rm_migrate.sh) is removed again, or the earlier file restored.
# ~/kws-releases is moved aside into ~/.kws-migration (not deleted) if the migration created it.
# Works for every state: after a failed preparation it only undoes allowed_signers and ~/kws-releases.
#
#   rm_rollback.sh [--auto] [--force]
#     --auto   called by rm_migrate.sh after a failed switch (no ARM check: services are already stopped)
#     --force  roll back even while rc reports ARMED
# Needs ~/.kws-migration/state written by rm_migrate.sh. A second run after success changes nothing.
set -u
set -o pipefail
umask 022
trap '' HUP PIPE

AUTO=0
FORCE=0
for a in "$@"; do
  case "$a" in
    --auto) AUTO=1 ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "unknown option $a" >&2; exit 2 ;;
  esac
done

LINK="$HOME/kws"
RELEASES="$HOME/kws-releases"
MIG="$HOME/.kws-migration"
STATE="$MIG/state"
SYSTEMD_USER="$HOME/.config/systemd/user"
PY="${KWS_MIGRATE_PYTHON:-python3}"
RC_STATUS_URL="${KWS_MIGRATE_RC_STATUS_URL:-http://127.0.0.1:8081/status}"
ACTIVE_TIMEOUT="${KWS_MIGRATE_ACTIVE_TIMEOUT:-60}"
SERVICES_OLD=(kambala-rc kambala-home kambala-display kambala-ui)
mkdir -p "$MIG"
LOG="$MIG/rollback-$(date +%Y%m%d-%H%M%S).log"

say() { printf '%s %s\n' "$(date +%T)" "$*" >> "$LOG"; printf '%s\n' "$*" 2> /dev/null || true; }
run() { printf '%s $ %s\n' "$(date +%T)" "$*" >> "$LOG"; "$@" >> "$LOG" 2>&1; }
die() { say "FAIL: $*"; say "log: $LOG"; exit 1; }
state_get() { sed -n "s/^$1=//p" "$STATE" | tail -n 1; }
state_set() {
  local k="$1" v="$2" tmp="$STATE.tmp"
  { grep -v "^$k=" "$STATE"; printf "%s=%q\n" "$k" "$v"; } > "$tmp" && mv -f "$tmp" "$STATE"
}

say "=== rm_rollback $(date -Is) user $(id -un) log $LOG"
if [ ! -f "$STATE" ]; then say "=== no $STATE: rm_migrate.sh changed nothing on this machine - nothing to do"; exit 0; fi
# shellcheck disable=SC1090
. "$STATE"   # STATUS STAMP VERSION OLD_DIR BACKUP REL_TOP RELEASES_PREEXISTED AS_BEFORE HAD_* LINGER_BEFORE
STATUS="${STATUS:-}"
SWITCHED=0
case "$STATUS" in
  rolled_back) say "=== already rolled back: nothing to do"; exit 0 ;;
  switching|switched|failed_switch|done) SWITCHED=1
    [ -n "${OLD_DIR:-}" ] && [ -n "${BACKUP:-}" ] || die "state file incomplete" ;;
  signers_placed|preparing|prepared|failed_prepare)
    say "   state '$STATUS': the switch never started - services, units and ~/kws itself untouched" ;;
  *) say "=== state '$STATUS': rm_migrate.sh changed nothing yet - nothing to do"; exit 0 ;;
esac

undo_signers() {  # after ~/kws is the old directory again
  case "${AS_BEFORE:-}" in
    absent) rm -f "$LINK/allowed_signers" && say "   removed ~/kws/allowed_signers (did not exist before)" ;;
    "") say "   allowed_signers: nothing recorded" ;;
    *) [ -f "$AS_BEFORE" ] && cp -p "$AS_BEFORE" "$LINK/allowed_signers" && say "   restored the earlier ~/kws/allowed_signers" ;;
  esac
}
releases_aside() {
  if [ "${RELEASES_PREEXISTED:-1}" = 0 ] && [ -d "$RELEASES" ] && [ ! -L "$RELEASES" ]; then
    local dst
    dst="$MIG/kws-releases.rolled-back-$(date +%Y%m%d-%H%M%S)"
    mv "$RELEASES" "$dst" || die "move $RELEASES aside"
    say "   ~/kws-releases moved to $dst (did not exist before the migration)"
  else
    say "   ~/kws-releases left in place"
  fi
}

if [ "$SWITCHED" = 0 ]; then
  [ -d "$LINK" ] && [ ! -L "$LINK" ] || die "~/kws is not a plain directory although the switch never started - resolve by hand"
  undo_signers
  releases_aside
  state_set STATUS rolled_back
  say "=== ROLLED BACK (preparation only): ~/kws/allowed_signers and ~/kws-releases undone"
  exit 0
fi

if [ "$AUTO" = 0 ] && [ "$FORCE" = 0 ]; then
  if ! "$PY" - "$RC_STATUS_URL" >> "$LOG" 2>&1 << 'EOF'
import json, sys, urllib.request
try:
    d = json.loads(urllib.request.urlopen(sys.argv[1], timeout=2).read().decode("utf-8"))
except Exception:
    sys.exit(0)
t = d.get("telemetry") if isinstance(d, dict) else None
fm = t.get("flight_mode") if isinstance(t, dict) else None
sys.exit(1 if d.get("arm_safe") is False or (isinstance(fm, dict) and fm.get("armed") is True) else 0)
EOF
  then die "rc reports ARMED - not while flying (--force to override)"; fi
fi

say "== R1. old directory present?"
if [ -d "$OLD_DIR" ] && [ ! -L "$OLD_DIR" ]; then
  say "   $OLD_DIR found"
elif [ -d "$LINK" ] && [ ! -L "$LINK" ]; then
  say "   ~/kws is still the old plain directory (the move never happened)"
else
  die "neither $OLD_DIR nor a plain ~/kws exists - NOT touching anything; see README 'Manual rollback'"
fi

say "== R2. stop services, switch kambala-update off"
run systemctl --user stop kambala-update "${SERVICES_OLD[@]}" || say "   (stop reported an error, continuing)"
if [ -f "$SYSTEMD_USER/kambala-update.service" ]; then
  run systemctl --user disable kambala-update || say "   (disable kambala-update reported an error, continuing)"
fi

say "== R3. ~/kws back to the old directory"
if [ -d "$OLD_DIR" ] && [ ! -L "$OLD_DIR" ]; then
  if [ -L "$LINK" ]; then
    rm -f "$LINK" || die "cannot remove link $LINK"          # only the link, never its target
  elif [ -e "$LINK" ]; then
    die "$LINK exists and is not a link while $OLD_DIR exists - resolve by hand (nothing removed)"
  fi
  mv "$OLD_DIR" "$LINK" || die "mv $OLD_DIR $LINK"
fi
[ -d "$LINK" ] && [ ! -L "$LINK" ] && [ -f "$LINK/.env" ] || die "~/kws is not the old directory with .env after R3"
say "   OK: ~/kws is the old directory again"
undo_signers

say "== R4. user units, labwc, pcmanfm from $BACKUP"
restore() {  # name path had
  local name="$1" path="$2" had="$3" aside="$BACKUP/$1.after-migration"
  rm -rf "$aside"
  if [ -e "$path" ]; then mv "$path" "$aside" || die "move aside $path"; fi
  if [ "$had" = 1 ]; then
    [ -e "$BACKUP/$name" ] || die "backup $BACKUP/$name missing"
    mkdir -p "$(dirname "$path")"
    cp -a "$BACKUP/$name" "$path" || die "restore $path"
    say "   restored $path (state after migration kept in $aside)"
  else
    say "   $path did not exist before; moved to $aside"
  fi
}
restore systemd_user "$SYSTEMD_USER" "${HAD_systemd_user:-1}"
restore labwc "$HOME/.config/labwc" "${HAD_labwc:-1}"
restore pcmanfm "$HOME/.config/pcmanfm" "${HAD_pcmanfm:-1}"
if [ "${LINGER_BEFORE:-}" = no ]; then run loginctl disable-linger "$(id -un)" || say "   (disable-linger failed)"; fi

say "== R5. ~/kws-releases"
releases_aside

say "== R6. start old services"
run systemctl --user daemon-reload || die "daemon-reload"
run systemctl --user start "${SERVICES_OLD[@]}" || say "   (start reported an error)"
deadline=$(( $(date +%s) + ACTIVE_TIMEOUT ))
while :; do
  bad=""
  for u in "${SERVICES_OLD[@]}"; do systemctl --user is-active --quiet "$u" || bad="$bad $u"; done
  [ -z "$bad" ] && break
  [ "$(date +%s)" -ge "$deadline" ] && break
  sleep 2
done
state_set STATUS rolled_back
if systemctl --user is-active --quiet kambala-update; then bad="$bad kambala-update(still active)"; fi
if [ -n "$bad" ]; then
  say "=== ROLLED BACK files and units, but not healthy:$bad (journalctl --user -u <unit>)"
  exit 1
fi
say "=== ROLLED BACK: ~/kws is the old directory, old units, ${SERVICES_OLD[*]} active, kambala-update off. Log: $LOG"
exit 0
