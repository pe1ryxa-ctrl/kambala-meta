#!/usr/bin/env bash
# HIL-чекліст переходу РМ, розділ 8 (KWS-032): трасування параметрів ELRS і таймінговий тест.
# Запуск на РМ під gans:  bash ~/kws-migration/hil_section8.sh prep|timing|cleanup
#   prep    — 8.1/8.2: KWS_RC_PARAM_TRACE=1 у ~/kws/.env (з резервною копією), перезапуск kambala-rc (лише при ARM вимкнено)
#   timing  — 8.6: окреме середовище ~/kws-hil-venv з коліс ~/kws-migration/hil-wheels, тест з KWS_TIMING_TESTS=1 і без
#   cleanup — 8.7: прибрати рядки трасування з .env, перезапуск kambala-rc (лише при ARM вимкнено)
# Кроки 8.3–8.5 (Max Power 10 → 25 → 10 у веб-інтерфейсі rc) — руками; Архітектор стежить за /status.
set -u
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
ENV="$HOME/kws/.env"
say() { printf '%s %s\n' "$(date +%T)" "$*"; }

arm_safe() {
    curl -s -m 3 http://127.0.0.1:8082/status | python3 -c 'import json,sys; print(json.load(sys.stdin)["rc"].get("arm_safe"))'
}
restart_rc() {
    [ "$(arm_safe)" = "True" ] || { say "FAIL: ARM не вимкнено (arm_safe != True) — rc не перезапускаю"; exit 1; }
    systemctl --user restart kambala-rc && sleep 3
    say "kambala-rc: $(systemctl --user is-active kambala-rc)"
}

case "${1:-}" in
prep)
    cp -p "$ENV" "$ENV.bak-hil8" && say "резервна копія: $ENV.bak-hil8"
    grep -q '^KWS_RC_PARAM_TRACE=' "$ENV" || printf '\n# HIL KWS-032 (тимчасово, прибирається hil_section8.sh cleanup)\nKWS_RC_PARAM_TRACE=1\nKWS_RC_PARAM_TRACE_MAX=5000\n' >> "$ENV"
    grep -E '^KWS_RC_PARAM_TRACE' "$ENV"
    restart_rc
    say "8.2 param-trace:"; curl -s 'http://127.0.0.1:8081/param-trace?limit=1' | head -c 300; echo
    ;;
timing)
    [ -d "$HOME/kws-migration/hil-wheels" ] || { say "FAIL: немає ~/kws-migration/hil-wheels"; exit 1; }
    [ -x "$HOME/kws-hil-venv/bin/python" ] || python3 -m venv "$HOME/kws-hil-venv"
    "$HOME/kws-hil-venv/bin/python" -m pip install -q --no-index --find-links "$HOME/kws-migration/hil-wheels" --find-links "$HOME/kws/wheels" pytest python-dotenv || { say "FAIL: pip install"; exit 1; }
    cd "$HOME/kws" || exit 1
    say "8.6 з KWS_TIMING_TESTS=1 (очікую 1 passed):"
    KWS_TIMING_TESTS=1 "$HOME/kws-hil-venv/bin/python" -m pytest tests/test_kws032_param_write.py -k param_trace_http_does_not_stall -q -p no:cacheprovider 2>&1 | tail -3
    say "8.6 без змінної (очікую 1 skipped):"
    "$HOME/kws-hil-venv/bin/python" -m pytest tests/test_kws032_param_write.py -k param_trace_http_does_not_stall -q -p no:cacheprovider 2>&1 | tail -2
    ;;
cleanup)
    sed -i '/^# HIL KWS-032 (тимчасово/d; /^KWS_RC_PARAM_TRACE=/d; /^KWS_RC_PARAM_TRACE_MAX=/d' "$ENV"
    say "рядків трасування в .env: $(grep -c '^KWS_RC_PARAM_TRACE' "$ENV")"
    restart_rc
    say "8.7 param-trace:"; curl -s 'http://127.0.0.1:8081/param-trace?limit=1' | head -c 200; echo
    ;;
*)
    echo "usage: $0 prep|timing|cleanup"; exit 2 ;;
esac
