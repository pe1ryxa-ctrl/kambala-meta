#!/usr/bin/env bash
# Kambala: швидкий деплой node-sim main на RPi 5 з живим відео V399 (KSIM-010) — щоб `node/sim` на РМ показував камеру.
# Запуск на RPi 5 під gans:  bash /tmp/rpi5_deploy_sim.sh <commit>
# Вхід: /tmp/kambala-nodesim-<commit>.tgz (+ .sha256) — git archive з ПК.
# Робить те саме, що deploy/push.ps1 (розпакування в ~/kambala/node-sim, deploy/install.sh з udev, рестарт служби),
# плюс у .env: KSIM_VIDEO_SOURCE=v4l2 (резервна копія .env поруч). Інших рядків .env не змінює.
set -u
C="${1:-}"; [ -n "$C" ] || { echo "usage: $0 <commit>"; exit 2; }
A="/tmp/kambala-nodesim-$C.tgz"; D="$HOME/kambala/node-sim"; TS=$(date +%Y%m%d-%H%M%S)
say() { printf '%s %s\n' "$(date +%T)" "$*"; }
fail() { say "FAIL: $*"; exit 1; }

say "== 0. архів"
[ -f "$A" ] && [ -f "$A.sha256" ] || fail "немає $A або .sha256"
[ "$(tr -d '\r' < "$A.sha256" | awk '{print $1}')" = "$(sha256sum "$A" | awk '{print $1}')" ] || fail "sha256 не збігається"
say "   OK sha256; V399: $(lsusb | grep -c '18ec:9186') шт."

say "== 1. .env: резервна копія і KSIM_VIDEO_SOURCE=v4l2"
cp -p "$D/.env" "$D/.env.bak-$TS" || fail "резервна копія .env"
if grep -q '^KSIM_VIDEO_SOURCE=' "$D/.env"; then sed -i 's/^KSIM_VIDEO_SOURCE=.*/KSIM_VIDEO_SOURCE=v4l2/' "$D/.env"; else printf '\nKSIM_VIDEO_SOURCE=v4l2\n' >> "$D/.env"; fi
grep -E '^(KSIM_VIDEO_SOURCE|KSIM_VIDEO_DEVICE|KSIM_VIDEO_PROFILE|VIDEO_INPUT)=' "$D/.env" | sed 's/^/   /'

say "== 2. розпакування $C у $D (як push.ps1)"
tar -xzf "$A" -C "$D" || fail "розпакування"
printf '%s\n' "$C" > "$D/.deployed_commit"

say "== 3. deploy/install.sh (служба + udev-правило V399)"
cd "$D" && bash deploy/install.sh "$D" "$USER" 2>&1 | tail -15 || fail "install.sh"

say "== 4. рестарт і перевірка"
sudo systemctl restart kambala-nodesim.service; sleep 8
say "   служба: $(systemctl is-active kambala-nodesim)"
ls -l /dev/ksim-v399 2>&1 | sed 's/^/   /'
say "   autosuspend V399: $(cat /sys/bus/usb/devices/*/idVendor 2>/dev/null | grep -c 18ec) пристрій; power/control: $(for d in /sys/bus/usb/devices/*; do [ "$(cat $d/idVendor 2>/dev/null)" = 18ec ] && cat $d/power/control; done)"
sudo journalctl -u kambala-nodesim -n 20 --no-pager | grep -iE "v4l2|capture|V399|НЕМАЄ|rtsp|error|Traceback" | cut -c1-200 | sed 's/^/   /'
say "   відкат .env: cp -p $D/.env.bak-$TS $D/.env && sudo systemctl restart kambala-nodesim"
say "=== DONE: node-sim $C на RPi 5"
