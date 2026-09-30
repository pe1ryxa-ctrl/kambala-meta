#!/usr/bin/env bash
# HIL-чекліст переходу РМ, розділ 4 (KWS-028): непідписаний і змінений реліз відхиляються до розпакування,
# рівно одне завантаження за 5 хв. Запуск на РМ під gans:  bash ~/kws-migration/hil_section4.sh
# Локальний тестовий сервер 127.0.0.1:8099 + drop-in для kambala-update; .env не змінюється.
# Прибирання (4.4) виконується завжди, навіть при збої (trap).
set -u
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
H="$HOME/hil028"
DROPIN_DIR="$HOME/.config/systemd/user/kambala-update.service.d"
WAIT_S="${HIL4_WAIT_S:-300}"
T="/releases/workstation/0.0.5/workstation-0.0.5.tgz"
FAIL=0
say() { printf '%s %s\n' "$(date +%T)" "$*"; }
check() { if [ "$2" = "$3" ]; then say "OK   $1: $2"; else say "FAIL $1: $2 (очікувано $3)"; FAIL=1; fi; }

cleanup() {
    say "== 4.4 прибирання"
    rm -f "$DROPIN_DIR/hil028.conf"; rmdir "$DROPIN_DIR" 2>/dev/null
    systemctl --user daemon-reload; systemctl --user restart kambala-update
    pkill -f "http.server 8099" 2>/dev/null
    rm -rf "$H"
    sleep 3
    say "kambala-update: $(systemctl --user is-active kambala-update); сервер: $(systemctl --user show kambala-update -p Environment | grep -o 'KWS_UPDATE_SERVER_URL=[^ ]*' || echo 'з .env (10.66.0.1)')"
}
trap cleanup EXIT

state() { curl -s -m 3 http://127.0.0.1:8082/status | python3 -c 'import json,sys; u=json.load(sys.stdin)["update"]; print(u["step"], u["ok"], u["message"])'; }
since_mark() { journalctl --user -u kambala-update --since "@$1" --no-pager; }

say "== підготовка: 0.0.5 з бойового сервера у $H, сервер 127.0.0.1:8099, drop-in"
mkdir -p "$H/releases/workstation/0.0.5" && cd "$H/releases/workstation/0.0.5" || exit 1
curl -fsSO "http://10.66.0.1$T" && curl -fsSO http://10.66.0.1/releases/workstation/0.0.5/release.json || { say "FAIL: не завантажено 0.0.5 з 10.66.0.1"; exit 1; }
cd "$H" || exit 1
python3 -m http.server 8099 --bind 127.0.0.1 >> "$H/http.log" 2>&1 &
sleep 1
mkdir -p "$DROPIN_DIR"
printf '[Service]\nEnvironment=KWS_UPDATE_SERVER_URL=http://127.0.0.1:8099\n' > "$DROPIN_DIR/hil028.conf"

say "== 4.1 непідписаний реліз, чекаю ${WAIT_S} с"
python3 -c 'import json; m=json.load(open("releases/workstation/0.0.5/release.json")); json.dump({"version":"0.0.5","url":"/releases/workstation/0.0.5/workstation-0.0.5.tgz","sha256":m["sha256"]}, open("releases/workstation/latest.json","w"))'
: > "$H/http.log"
M1=$(date +%s)
systemctl --user daemon-reload && systemctl --user restart kambala-update
sleep "$WAIT_S"
check "4.1 завантажень" "$(grep -c "GET $T" "$H/http.log")" 1
check "4.1 ~/kws" "$(readlink -f "$HOME/kws" | grep -o 'workstation-[0-9.]*$')" workstation-0.0.3
check "4.1 ~/kws-releases/0.0.5 відсутній" "$([ -e "$HOME/kws-releases/0.0.5" ] && echo є || echo немає)" немає
say "стан: $(state)"
since_mark "$M1" | grep -iE 'verif|signed|підпис' | tail -3

say "== 4.2 змінений реліз, чекаю ${WAIT_S} с"
printf X >> "releases/workstation/0.0.5/workstation-0.0.5.tgz"
python3 -c 'import json,hashlib; p="releases/workstation/0.0.5/"; m=json.load(open(p+"release.json")); a=open(p+"workstation-0.0.5.tgz","rb").read(); json.dump({"version":"0.0.5","url":"/releases/workstation/0.0.5/workstation-0.0.5.tgz","sha256":hashlib.sha256(a).hexdigest(),"sig":m["sig"],"signer":m["signer"]}, open("releases/workstation/latest.json","w"))'
: > "$H/http.log"
M2=$(date +%s)
sleep "$WAIT_S"
check "4.2 завантажень" "$(grep -c "GET $T" "$H/http.log")" 1
check "4.2 ~/kws" "$(readlink -f "$HOME/kws" | grep -o 'workstation-[0-9.]*$')" workstation-0.0.3
say "стан: $(state)"
since_mark "$M2" | grep -iE 'verif|signature|підпис' | tail -3

say "== 4.3 Traceback за час розділу"
check "4.3 Traceback" "$(since_mark "$M1" | grep -c Traceback)" 0

trap - EXIT
cleanup

say "== 4.5 справжній підпис 0.0.5 з бойового сервера"
ssh-keygen -Y verify -f "$HOME/kws/allowed_signers" -I gans-master-1 -n kambala-release \
    -s <(curl -fs http://10.66.0.1/releases/workstation/0.0.5/workstation-0.0.5.tgz.sig) \
    < <(curl -fs "http://10.66.0.1$T") || FAIL=1

[ "$FAIL" = 0 ] && say "=== РОЗДІЛ 4: усі перевірки OK" || say "=== РОЗДІЛ 4: є FAIL — див. вище"
exit "$FAIL"
