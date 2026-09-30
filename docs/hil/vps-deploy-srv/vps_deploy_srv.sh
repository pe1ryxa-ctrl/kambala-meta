#!/usr/bin/env bash
# Kambala: розгортання server main на VPS (крок 1 з 4 — контейнери; тунель, фаєрвол і реєстр НЕ чіпаються).
# Запуск від root на VPS:
#   bash /tmp/kws-srv/vps_deploy_srv.sh <commit>            # dry-run (за замовчуванням): перевірки й перелік змін, НІЧОГО не змінює
#   bash /tmp/kws-srv/vps_deploy_srv.sh <commit> --apply    # розгортання
# Вхід: /tmp/kws-srv/server-<commit>.tgz (git archive з ПК) і .sha256 поруч.
# Що робить --apply:
#   1. src.new з архіву → /opt/kambala/src (старий → src.prev-<час>), DEPLOYED_COMMIT = <commit>;
#   2. compose.yml з infra/ репозиторію з живою правкою `context: ..` → `context: /opt/kambala/src`
#      (старий → compose.yml.bak-<час>);
#   3. дашборд Grafana, deploy.sh, apply_firewall.sh, nftables.conf (лише копія, фаєрвол НЕ застосовується);
#   4. ./deploy.sh (KSRV-022): метрики, права, таймер, build relay devices releases fcbridge, up -d, перевірки після up.
# Не змінює: .env, тунель WireGuard (apply.sh), фаєрвол (nft), NAT, реєстр вузлів (nodes.yaml).
set -u
C="${1:-}"; MODE="${2:---dry-run}"
[ -n "$C" ] || { echo "usage: $0 <commit> [--apply]"; exit 2; }
[ "$MODE" = "--dry-run" ] || [ "$MODE" = "--apply" ] || { echo "usage: $0 <commit> [--apply]"; exit 2; }
ROOT=/opt/kambala; IN=/tmp/kws-srv; A="$IN/server-$C.tgz"; TS=$(date +%Y%m%d-%H%M%S)
STAGE="$ROOT/.stage-$C"
say() { printf '%s %s\n' "$(date +%T)" "$*"; }
fail() { say "FAIL: $*"; exit 2; }
[ "$(id -u)" = 0 ] || fail "запускати від root"

say "== 0. архів $A"
[ -f "$A" ] && [ -f "$A.sha256" ] || fail "немає $A або $A.sha256"
want=$(tr -d '\r' < "$A.sha256" | awk '{print $1}'); have=$(sha256sum "$A" | awk '{print $1}')
[ "$want" = "$have" ] || fail "sha256 не збігається: $have ≠ $want"
say "   OK sha256 $have"

say "== 1. розпакування в $STAGE (живе не чіпається)"
rm -rf "$STAGE"; mkdir -p "$STAGE/src" && tar -xzf "$A" -C "$STAGE/src" || fail "розпакування"
[ -f "$STAGE/src/Dockerfile" ] && [ -f "$STAGE/src/infra/compose.yml" ] && [ -f "$STAGE/src/infra/deploy.sh" ] || fail "у архіві немає Dockerfile / infra/compose.yml / infra/deploy.sh"
printf '%s\n' "$C" > "$STAGE/src/DEPLOYED_COMMIT"
say "   зараз на VPS: $(cat $ROOT/src/DEPLOYED_COMMIT 2>/dev/null || echo невідомо) → буде $C"

say "== 2. compose.yml з живою правкою context"
sed 's#^\(\s*context:\s*\)\.\.\s*$#\1/opt/kambala/src#' "$STAGE/src/infra/compose.yml" > "$STAGE/compose.yml"
n_ctx=$(grep -c 'context: /opt/kambala/src' "$STAGE/compose.yml"); n_dots=$(grep -cE 'context:\s*\.\.\s*$' "$STAGE/compose.yml")
[ "$n_dots" = 0 ] && [ "$n_ctx" -ge 4 ] || fail "правка context: /opt/kambala/src=$n_ctx, лишилось '..'=$n_dots"
say "   OK context → /opt/kambala/src ×$n_ctx"
docker compose -f "$STAGE/compose.yml" --project-directory "$ROOT" --project-name kambala --env-file "$ROOT/.env" config -q \
  || fail "docker compose config новим compose.yml"
say "   OK docker compose config -q (новий compose.yml, живий .env)"
say "   різниця compose.yml (живий → новий):"
diff "$ROOT/compose.yml" "$STAGE/compose.yml" | sed 's/^/     /' | head -60

say "== 3. інші файли з infra/ (що зміниться)"
for f in grafana/provisioning/dashboards/json/system_status.json deploy.sh apply_firewall.sh nftables.conf; do
    if [ ! -f "$ROOT/$f" ]; then say "   нове:   $f"
    elif ! cmp -s "$ROOT/$f" "$STAGE/src/infra/$f"; then say "   зміна:  $f"
    else say "   без змін: $f"; fi
done
for f in caddy/Caddyfile mediamtx/mediamtx.yml prometheus/prometheus.yml monitoring/wg_handshake_metrics.sh; do
    cmp -s "$ROOT/$f" "$STAGE/src/infra/$f" && say "   без змін: $f" || say "   ⚠ РОЗБІЖНІСТЬ (скрипт НЕ перезаписує, розібрати вручну): $f"
done

if [ "$MODE" = "--dry-run" ]; then
    say "== DRY-RUN: нічого не змінено. Розгортання: bash $0 $C --apply"
    exit 0
fi

say "== 4. APPLY: заміна src і compose.yml (резервні копії з міткою $TS)"
cp -p "$ROOT/compose.yml" "$ROOT/compose.yml.bak-$TS"
mv "$ROOT/src" "$ROOT/src.prev-$TS" && mv "$STAGE/src" "$ROOT/src" || fail "заміна src (перевір $ROOT/src.prev-$TS)"
install -m 0644 "$STAGE/compose.yml" "$ROOT/compose.yml"
install -m 0644 "$ROOT/src/infra/grafana/provisioning/dashboards/json/system_status.json" "$ROOT/grafana/provisioning/dashboards/json/system_status.json"
install -m 0755 "$ROOT/src/infra/deploy.sh" "$ROOT/deploy.sh"
install -m 0755 "$ROOT/src/infra/apply_firewall.sh" "$ROOT/apply_firewall.sh"
install -m 0644 "$ROOT/src/infra/nftables.conf" "$ROOT/nftables.conf"
rm -rf "$STAGE"
say "   OK src=$(cat $ROOT/src/DEPLOYED_COMMIT), compose.yml, дашборд, deploy.sh, apply_firewall.sh, nftables.conf (фаєрвол НЕ застосовано)"

say "== 5. deploy.sh (dry-run, потім --apply)"
cd "$ROOT" || fail "cd $ROOT"
./deploy.sh || fail "deploy.sh dry-run (живе вже замінено — відкат нижче)"
./deploy.sh --apply; rc=$?

say "== 6. після розгортання"
docker compose -f "$ROOT/compose.yml" ps --format '{{.Name}} {{.Status}}' | sort
ss -ltnp | grep ':6761' || say "   ⚠ 6761 не слухає"
say "   liveness-пири: $(docker exec devices sh -c 'echo $KSRV_LIVENESS_PEERS' 2>/dev/null)"
say "   відкат за потреби:  cd $ROOT && mv src src.bad-$TS && mv src.prev-$TS src && cp -p compose.yml.bak-$TS compose.yml && docker compose -f compose.yml up -d --build relay devices releases && docker compose -f compose.yml rm -sf fcbridge"
[ "$rc" = 0 ] && say "=== DONE: server $C розгорнуто" || say "=== deploy.sh --apply код $rc — див. вище"
exit "$rc"
