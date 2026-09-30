#!/usr/bin/env bash
# Kambala: KSRV-018, перший крок — створити /etc/kambala/wg-peers із ЖИВОЇ конфігурації wg0 (нічого не змінює в ядрі),
# потім apply.sh --dry-run (очікування: живе ядро == рендер, змін немає).
# Запуск від root на VPS:  bash /tmp/kws-srv/vps_wg_peers_init.sh
# Секрети (PSK) пишуться лише у файл (600 root) і ніде не друкуються; публічні ключі в виводі скорочено.
set -u
P=/etc/kambala/wg-peers
say() { printf '%s %s\n' "$(date +%T)" "$*"; }
[ "$(id -u)" = 0 ] || { say "FAIL: від root"; exit 2; }
if [ -e "$P" ]; then say "файл $P уже існує — не перезаписую; лише dry-run"; else
  umask 077
  TMPF=$(mktemp)
  wg showconf wg0 | awk '
    function flush(){ if(pk=="") return; nm=names[ai1]; if(nm=="") nm="peer-" substr(ai1,1,index(ai1,"/")-1);
      gsub(/[.]/,"-",nm); print "name = " nm; if(nodes[ai1]!="") print "node_id = " nodes[ai1];
      print "public_key = " pk; print "allowed_ips = " ai; if(ka!="") print "persistent_keepalive = " ka;
      if(psk!="") print "preshared_key = " psk; print ""; pk=ai=ka=psk=ai1="" }
    BEGIN{ names["10.66.0.2/32"]="pc"; names["10.66.0.3/32"]="workstation"; names["10.66.0.10/32"]="sim-rpi5"; names["10.66.0.11/32"]="hil-mikrotik";
           nodes["10.66.0.10/32"]="sim"; nodes["10.66.0.11/32"]="hil" }
    /^\[Peer\]/{ flush(); next }
    /^PublicKey/{ pk=$3 } /^PresharedKey/{ psk=$3 } /^PersistentKeepalive/{ ka=$3 }
    /^AllowedIPs/{ sub(/^AllowedIPs *= */,""); ai=$0; gsub(/ /,"",ai); split(ai,a,","); ai1=a[1] }
    END{ flush() }' > "$TMPF" || { say "FAIL: wg showconf"; rm -f "$TMPF"; exit 1; }
  n_live=$(wg show wg0 peers | wc -l); n_file=$(grep -c '^public_key' "$TMPF")
  [ "$n_live" = "$n_file" ] && [ "$n_file" -gt 0 ] || { say "FAIL: пирів у ядрі $n_live, у файлі $n_file"; rm -f "$TMPF"; exit 1; }
  install -m 600 -o root -g root "$TMPF" "$P" && rm -f "$TMPF"
  say "створено $P ($n_file пирів, 600 root)"
fi
say "== вміст (ключі скорочено, PSK приховано):"
sed -E 's/^(public_key = .{8}).*/\1…/; s/^(preshared_key = ).*/\1<прихований>/' "$P" | sed 's/^/   /'
say "== apply.sh --dry-run"
cd /opt/kambala/src/infra/wireguard || { say "FAIL: немає /opt/kambala/src/infra/wireguard"; exit 1; }
bash ./apply.sh --dry-run 2>&1 | sed -E 's/([A-Za-z0-9+\/]{43}=)/<key>/g' | tail -60
say "=== DONE (ядро не змінювалось)"
