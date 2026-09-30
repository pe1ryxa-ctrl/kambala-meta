#!/usr/bin/env bash
# Kambala: HIL KSRV-024 (частина без ізоляції) + KSRV-026 (apply.sh під AppArmor) на VPS після деплою 94d7599.
# Запуск від root на VPS:  bash /tmp/kws-srv/vps_hil_ksrv024_026.sh
# НЕ ізолює вузли і не робить штучного дрейфу (це HIL KSRV-019/024 ч. 2 — після процедури повернення вузла).
# Змінює лише: /etc/wireguard/wg0.conf перезаписується apply.sh (очікування — «ідентична», ядро без змін).
# Ключі у виводі замасковано; PSK/приватні ключі не друкуються.
set -u
W=/opt/kambala/src/infra/wireguard
say() { printf '%s %s\n' "$(date +%T)" "$*"; }
mask() { sed -E 's/([A-Za-z0-9+\/]{43}=)/<key>/g'; }
[ "$(id -u)" = 0 ] || { say "FAIL: від root"; exit 2; }
[ "$(cat /opt/kambala/src/DEPLOYED_COMMIT 2>/dev/null)" = 94d7599 ] || say "⚠ DEPLOYED_COMMIT = $(cat /opt/kambala/src/DEPLOYED_COMMIT 2>/dev/null) (очікую 94d7599)"
cd "$W" || { say "FAIL: немає $W"; exit 2; }
T0=$(date '+%Y-%m-%d %H:%M:%S')
PEERS0=$(wg show wg0 peers | sort | sha256sum | cut -c1-12); N0=$(wg show wg0 peers | wc -l)

say "== 1. node_id у живому /etc/kambala/wg-peers (очікую: sim-rpi5 → sim, hil-mikrotik → hil)"
grep -E '^(name|node_id) *=' /etc/kambala/wg-peers | sed 's/^/   /'

say "== 2. check.sh (очікую rc 0)"
bash ./check.sh 2>&1 | mask | tail -15 | sed 's/^/   /'; say "   check.sh rc=${PIPESTATUS[0]}"

say "== 3. KSRV-024: wg set … remove з ключем, якого немає в ядрі (очікую rc 0, пирів без змін)"
ABSENT=$(wg genkey | wg pubkey)
wg set wg0 peer "$ABSENT" remove; say "   rc=$?; пирів: $N0 → $(wg show wg0 peers | wc -l)"

say "== 4. KSRV-026: apply.sh --dry-run"
bash ./apply.sh --dry-run 2>&1 | mask | tail -25 | sed 's/^/   /'; say "   dry-run rc=${PIPESTATUS[0]}"

say "== 5. KSRV-026: apply.sh (очікую «ідентична», запис wg0.conf, syncconf без змін у ядрі)"
cp -p /etc/wireguard/wg0.conf "/root/wg0.conf.before-ksrv026-$(date +%Y%m%d-%H%M%S)"
bash ./apply.sh 2>&1 | mask | tail -25 | sed 's/^/   /'; say "   apply rc=${PIPESTATUS[0]}"
PEERS1=$(wg show wg0 peers | sort | sha256sum | cut -c1-12)
[ "$PEERS0" = "$PEERS1" ] && say "   OK пири ядра ті самі ($N0)" || say "   ⚠ НАБІР ПИРІВ ЗМІНИВСЯ: $PEERS0 → $PEERS1"
wg show wg0 latest-handshakes | while read -r k t; do printf '   %s… %ss\n' "${k:0:6}" "$(( $(date +%s) - t ))"; done

say "== 6. check.sh після apply (очікую rc 0)"
bash ./check.sh >/dev/null 2>&1; say "   check.sh rc=$?"

say "== 7. AppArmor DENIED з $T0 (очікую порожньо) і залишки stage (очікую порожньо)"
journalctl -k --since "$T0" --no-pager | grep -i 'apparmor="DENIED"' | cut -c1-200 | sed 's/^/   /'
ls -a /etc/wireguard | grep kambala-stage | sed 's/^/   залишок: /'
say "== 8. deploy.sh --dry-run"
(cd /opt/kambala && bash ./deploy.sh --dry-run) 2>&1 | tail -8 | sed 's/^/   /'
say "=== DONE (резервна копія wg0.conf — /root/wg0.conf.before-ksrv026-*)"
