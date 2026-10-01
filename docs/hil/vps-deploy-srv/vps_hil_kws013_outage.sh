#!/usr/bin/env bash
# Kambala HIL KWS-013: два обриви каналу вузла hil по ~7 с з інтервалом 20 с (лише шлях сервер ↔ Streamer).
# Запуск від root на VPS:  bash /tmp/kws-srv/vps_hil_kws013_outage.sh
# Як: тимчасовий маршрут blackhole на адресу Streamer (192.168.13.21/32) — MediaMTX втрачає джерело node/hil*,
# РМ бачить зникнення потоку. Тунель WireGuard, MikroTik і керування (FBI-B) НЕ чіпаються.
# Запобіжник: незалежний таймер systemd прибере маршрут через 60 с, навіть якщо сесію обірве.
set -u
IP=192.168.13.21/32
say() { printf '%s %s\n' "$(date +%T)" "$*"; }
[ "$(id -u)" = 0 ] || { say "FAIL: від root"; exit 2; }
ip route show "$IP" | grep -q blackhole && { say "FAIL: blackhole уже стоїть — прибери: ip route del blackhole $IP"; exit 2; }
systemd-run --on-active=60 --unit=kws013-unblock --quiet ip route del blackhole "$IP" 2>/dev/null \
  || say "⚠ таймер-запобіжник не створено (є з минулого запуску?) — далі прибираю вручну"
for n in 1 2; do
  ip route add blackhole "$IP" && say "ОБРИВ $n: шлях до Streamer закрито"
  sleep 7
  ip route del blackhole "$IP" && say "ОБРИВ $n: шлях відновлено"
  [ "$n" = 1 ] && { say "пауза 20 с"; sleep 20; }
done
systemctl stop kws013-unblock.timer 2>/dev/null; systemctl reset-failed kws013-unblock.service 2>/dev/null
ip route show "$IP" | grep -q blackhole && say "⚠ маршрут лишився!" || say "=== DONE: маршрут прибрано, обидва обриви виконано"
