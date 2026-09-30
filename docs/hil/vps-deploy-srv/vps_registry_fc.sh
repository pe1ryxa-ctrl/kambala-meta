#!/usr/bin/env bash
# Kambala: крок 3 розгортання KSRV-021 — польотник бокса 1 вузла hil у реєстрі вузлів (fc_endpoints).
# Запуск від root на VPS:
#   bash /tmp/kws-srv/vps_registry_fc.sh             # dry-run: показує, що зміниться, нічого не пише
#   bash /tmp/kws-srv/vps_registry_fc.sh --apply     # резервна копія nodes.yaml, запис, перевірка YAML, рестарт fcbridge
# Реєстр — у томі kambala_nodes_data (/etc/kambala/nodes.yaml). Ендпоінт: RouterOS /port remote-access на MikroTik
# вузла hil, 10.66.0.11:5790 (доступ лише з 10.66.0.1). Інших вузлів і полів не чіпає.
set -u
MODE="${1:---dry-run}"
EP="${KWS_FC_EP:-10.66.0.11:5790}"
V=$(docker volume inspect kambala_nodes_data --format '{{.Mountpoint}}') || { echo "FAIL: том kambala_nodes_data"; exit 2; }
F="$V/nodes.yaml"; TS=$(date +%Y%m%d-%H%M%S); NEW=$(mktemp)
say() { printf '%s %s\n' "$(date +%T)" "$*"; }
[ -f "$F" ] || { say "FAIL: немає $F"; exit 2; }
if awk '/^  - id: "hil"/{h=1;next} /^  - id:/{h=0} h&&/fc_endpoints:/{f=1} END{exit !f}' "$F"; then
    say "у записі hil уже є fc_endpoints — нічого не роблю:"; awk '/^  - id: "hil"/{h=1} /^  - id: "sim"/{h=0} h' "$F" | grep -A3 fc_endpoints; exit 0
fi
# вставити після рядка write_allowed запису hil (4 пробіли відступу — як у сусідніх полях)
awk -v ep="$EP" '/^  - id: "hil"/{h=1} /^  - id:/&&!/"hil"/{h=0} {print} h&&/^    write_allowed:/{print "    fc_endpoints:"; print "      1: \"" ep "\""; h=0; done=1} END{exit !done}' "$F" > "$NEW" \
  || { say "FAIL: у записі hil не знайдено write_allowed — вставляти нікуди"; rm -f "$NEW"; exit 2; }
say "== зміна nodes.yaml:"; diff "$F" "$NEW" | sed 's/^/   /'
docker exec -i devices python -c 'import sys,yaml; d=yaml.safe_load(sys.stdin); h=[n for n in d["nodes"] if n["id"]=="hil"][0]; print("   YAML OK, hil.fc_endpoints =", h.get("fc_endpoints"))' < "$NEW" \
  || { say "FAIL: новий YAML не читається"; rm -f "$NEW"; exit 2; }
timeout 3 bash -c "</dev/tcp/${EP%:*}/${EP#*:}" && say "   ендпоінт $EP відкритий" || say "   ⚠ ендпоінт $EP не відповідає (запис усе одно можливий)"
if [ "$MODE" != "--apply" ]; then say "== DRY-RUN: нічого не змінено. Запис: bash $0 --apply"; rm -f "$NEW"; exit 0; fi
cp -p "$F" "$F.bak-$TS" && install -m "$(stat -c %a "$F")" -o "$(stat -c %u "$F")" -g "$(stat -c %g "$F")" "$NEW" "$F" && rm -f "$NEW" \
  || { say "FAIL: запис (резервна копія $F.bak-$TS)"; exit 1; }
say "== записано (резервна копія $F.bak-$TS), рестарт fcbridge"
docker compose -f /opt/kambala/compose.yml restart fcbridge >/dev/null 2>&1; sleep 8
docker ps --format '{{.Names}} {{.Status}}' | grep fcbridge
docker logs --since 20s fcbridge 2>&1 | tail -5
say "   відкат: cp -p $F.bak-$TS $F && docker compose -f /opt/kambala/compose.yml restart fcbridge"
say "=== DONE"
