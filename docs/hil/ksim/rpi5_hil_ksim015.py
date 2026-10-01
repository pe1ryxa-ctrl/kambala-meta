#!/usr/bin/env python3
"""Kambala HIL KSIM-015 на RPi 5: модель заряду бокса 1 (CC→CV→READY), правила C1a 2026-10-01.

Запуск на RPi 5 (venv node-sim), служба з прискоренням часу заряду (KSIM_CHARGE_TIME_SCALE у .env):
  ~/kambala/node-sim/.venv/bin/python /tmp/rpi5_hil_ksim015.py [секунд_спостереження]
Змінює лише стан віртуального боксу 1; наприкінці зупиняє зарядку.
"""
import sys
import time

from pymavlink import mavutil
from pymavlink.dialects.v20 import ardupilotmega as m

COMP = 25
RES = {0: "ACCEPTED", 2: "DENIED", 3: "UNSUPPORTED", 4: "FAILED"}
STATE = {0: "STANDBY", 1: "CHARGING", 2: "READY", 3: "ACTIVATED", 4: "OPEN", 5: "LAUNCHED", 6: "FAULT"}
WATCH = float(sys.argv[1]) if len(sys.argv) > 1 else 120.0

c = mavutil.mavlink_connection("tcp:127.0.0.1:1311", source_system=255, source_component=190)
st = {"mode": None, "i": None, "t": None, "cells": None, "pct": None}
seq_last, gaps = {}, 0


def pump(sec, want_ack=None):
    global gaps
    end, ack = time.time() + sec, None
    while time.time() < end:
        msg = c.recv_match(blocking=True, timeout=0.2)
        if msg is None:
            continue
        cid, s = msg.get_srcComponent(), msg.get_seq()
        if cid in seq_last and (s - seq_last[cid]) % 256 != 1:
            gaps += 1
        seq_last[cid] = s
        if cid != COMP:
            continue
        t = msg.get_type()
        if t == "HEARTBEAT":
            st["mode"] = msg.custom_mode
        elif t == "NAMED_VALUE_FLOAT":
            n = msg.name.rstrip("\x00") if isinstance(msg.name, str) else msg.name.decode().rstrip("\x00")
            if n == "I_CHG":
                st["i"] = round(msg.value, 2)
            elif n == "TEMP_BAT":
                st["t"] = round(msg.value, 1)
        elif t == "BATTERY_STATUS":
            v = [x for x in msg.voltages if x != 65535]
            st["cells"] = round(sum(v) / 1000, 2) if v else None
            st["pct"] = msg.battery_remaining
        elif t == "COMMAND_ACK" and want_ack is not None and msg.command == want_ack:
            ack = msg.result
            end = min(end, time.time() + 0.5)
    return ack


def cmd(sysid, command, p1, p2):
    c.mav.command_long_send(sysid, COMP, command, 0, p1, p2, 0, 0, 0, 0, 0)
    return RES.get(pump(3, want_ack=command), "немає ACK")


def show(tag):
    print(f"{tag}: стан={STATE.get(st['mode'], st['mode'])} V={st['cells']} В заряд={st['pct']}% I_CHG={st['i']} А TEMP_BAT={st['t']} °C")


hb = c.recv_match(type="HEARTBEAT", blocking=True, timeout=10)
SYS = hb.get_srcSystem()
pump(3)
show("старт")
R, S = m.MAV_CMD_DO_SET_RELAY, m.MAV_CMD_DO_SET_SERVO
print("широкомовне серво (system 0) →", cmd(0, S, 1, 2000), "(очікую DENIED)")
print("широкомовне реле обігріву (system 0) →", cmd(0, R, 2, 1), "(очікую DENIED)")
print("зарядка увімк. →", cmd(SYS, R, 1, 1), "(очікую ACCEPTED)")
first = None
t0 = time.time()
while time.time() - t0 < WATCH:
    pump(10)
    show(f"+{int(time.time() - t0)} с")
    first = first or dict(st)
    if st["mode"] == 2:
        break
pump(2)
ok_charge = first and st["cells"] and first["cells"] and st["cells"] >= first["cells"]
print(f"{'PASS' if ok_charge else 'FAIL'}  напруга не спадає під зарядом ({first and first['cells']} → {st['cells']} В)")
print(f"{'PASS' if st['mode'] == 2 else 'INFO'}  перехід у READY {'є' if st['mode'] == 2 else 'не за час спостереження (збільш KSIM_CHARGE_TIME_SCALE або час)'}")
print("зарядка вимк. →", cmd(SYS, R, 1, 0))
print(f"{'PASS' if gaps == 0 else 'FAIL'}  розриви seq: {gaps}")
