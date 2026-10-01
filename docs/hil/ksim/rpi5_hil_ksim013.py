#!/usr/bin/env python3
"""Kambala HIL KSIM-013 на RPi 5: команди боксу 1 по MAVLink :1311 (localhost), перевірка ACK, стану, DIAG і seq.

Запуск на RPi 5 (venv node-sim):  ~/kambala/node-sim/.venv/bin/python /tmp/rpi5_hil_ksim013.py
Змінює лише стан віртуального боксу 1 симулятора; наприкінці повертає його в STANDBY (живлення борту вимкнено).
"""
import time
from collections import defaultdict

from pymavlink import mavutil
from pymavlink.dialects.v20 import ardupilotmega as m

COMP = 25  # бокс 1 = MAV_COMP_ID_USER1
RES = {0: "ACCEPTED", 2: "DENIED", 3: "UNSUPPORTED", 4: "FAILED"}
STATE = {0: "STANDBY", 1: "CHARGING", 2: "READY", 3: "ACTIVATED", 4: "OPEN", 5: "LAUNCHED", 6: "FAULT"}

c = mavutil.mavlink_connection("tcp:127.0.0.1:1311", source_system=255, source_component=190)
last_seq = {}
gaps = defaultdict(int)
st = {"mode": None, "diag": None, "lock": None, "lid": None}
texts = []


def pump(sec, want_ack=None):
    end = time.time() + sec
    ack = None
    while time.time() < end:
        msg = c.recv_match(blocking=True, timeout=0.2)
        if msg is None:
            continue
        cid = msg.get_srcComponent()
        s = msg.get_seq()
        if cid in last_seq and (s - last_seq[cid]) % 256 != 1:
            gaps[cid] += 1
        last_seq[cid] = s
        if cid != COMP:
            continue
        t = msg.get_type()
        if t == "HEARTBEAT":
            st["mode"] = msg.custom_mode
        elif t == "NAMED_VALUE_INT":
            n = msg.name.rstrip("\x00") if isinstance(msg.name, str) else msg.name.decode().rstrip("\x00")
            if n == "DIAG":
                st["diag"] = msg.value
            elif n == "LOCK":
                st["lock"] = msg.value
            elif n == "LID":
                st["lid"] = msg.value
        elif t == "STATUSTEXT":
            texts.append((msg.severity, msg.text))
        elif t == "COMMAND_ACK" and want_ack is not None and msg.command == want_ack:
            ack = msg.result
            if sec <= 3:
                end = min(end, time.time() + 0.5)
    return ack


def cmd(name, command, p1, p2, expect, settle=1.5, tsys=None):
    sysid = SYS if tsys is None else tsys
    c.mav.command_long_send(sysid, COMP, command, 0, p1, p2, 0, 0, 0, 0, 0)
    ack = pump(3, want_ack=command)
    pump(settle)
    ok = RES.get(ack, ack) == expect
    print(f"{'PASS' if ok else 'FAIL'}  {name}: ACK={RES.get(ack, ack)} (очікую {expect}); стан={STATE.get(st['mode'], st['mode'])} DIAG={st['diag']} LOCK={st['lock']} LID={st['lid']}")
    return ok


hb = c.recv_match(type="HEARTBEAT", blocking=True, timeout=10)
SYS = hb.get_srcSystem()  # pymavlink не бере target_system з heartbeat ONBOARD_CONTROLLER — задаємо явно
print(f"зв'язок: system={SYS}")
pump(3)
print(f"старт: стан={STATE.get(st['mode'], st['mode'])} DIAG={st['diag']} LOCK={st['lock']} LID={st['lid']}")
gaps.clear()
R, S = m.MAV_CMD_DO_SET_RELAY, m.MAV_CMD_DO_SET_SERVO
res = []
res.append(cmd("замки замкнути", S, 1, 1000, "ACCEPTED"))
res.append(cmd("стулки відкрити при замкнених замках → інтерлок", S, 2, 2000, "DENIED"))
res.append(cmd("живлення борту увімк.", R, 0, 1, "ACCEPTED", settle=4))
res.append(cmd("DIAG увімк.", R, 4, 1, "ACCEPTED"))
diag_on = st["diag"] == 1
sev = [sv for sv, tx in texts if "DIAG" in tx]
res.append(cmd("живлення борту вимк. → DIAG скинуто, STANDBY", R, 0, 0, "ACCEPTED", settle=3))
diag_reset = st["diag"] == 0 and st["mode"] == 0
print(f"{'PASS' if diag_on else 'FAIL'}  DIAG=1 після увімкнення")
print(f"{'PASS' if diag_reset else 'FAIL'}  DIAG=0 і STANDBY після вимкнення живлення")
print(f"{'PASS' if sev and all(x == 4 for x in sev) else 'FAIL'}  STATUSTEXT про DIAG — WARNING(4): {sev}")
print("== серія 20 команд (обігрів увімк./вимк.) для перевірки seq")
for i in range(20):
    c.mav.command_long_send(SYS, COMP, R, 0, 2, i % 2, 0, 0, 0, 0, 0)
    pump(0.15)
pump(3)
print(f"{'PASS' if sum(gaps.values()) == 0 else 'FAIL'}  розриви seq за весь прогін: {dict(gaps) or 0}")
print("== широкомовна команда (target_system=0) на серво — за C1a 01.10 має бути DENIED (відомий хвіст B: зараз виконується)")
cmd("broadcast: замки відкрити", S, 1, 2000, "DENIED", tsys=0)
cmd("повернути замки", S, 1, 1000, "ACCEPTED")
print(f"=== {'ВСЕ PASS' if all(res) and diag_on and diag_reset and sum(gaps.values()) == 0 else 'Є FAIL'}")
