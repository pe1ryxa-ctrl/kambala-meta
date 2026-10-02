#!/bin/bash
# Від скла до скла без композитора на РМ-1: зупиняє сесію (labwc), запускає g2g_kms.py (DRM обох екранів в одному процесі),
# потім відновлює сесію через getty@tty1. Лише РМ-1 (не бережемо як РМ).
TAG=${1:-kms}; N=${N:-60}
cd ~/latency
pkill -x -u "$(id -u)" labwc; sleep 4
pgrep -a -x labwc && echo "УВАГА: labwc ще працює"
sudo -n env ROI_ASUS=${ROI_ASUS:-0.18,0.25,0.45,0.60} ROI_DW=${ROI_DW:-0.74,0.78,0.83,0.90} G2G_RAW=/home/$(id -un)/latency/${TAG}.raw \
  timeout $(( N * 2 + 60 )) python3 g2g_kms.py "$TAG" "$N" 1.0 2>&1 | tail -2
sudo -n systemctl restart getty@tty1; sleep 25
pgrep -a -x labwc || echo "labwc НЕ запущено"; systemctl --user is-active kambala-display; echo DONE
