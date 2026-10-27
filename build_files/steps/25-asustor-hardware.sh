#!/bin/bash
# Hardware AS6702T: sensori e ventola regolata sulla temperatura della CPU.
source "$(dirname "$0")/vars.sh"

dnf5 install -y lm_sensors
chmod 755 /usr/libexec/nas-os/fancontrol-config
# Se il driver non carica, fancontrol fallisce e la ventola resta al valore del BIOS
systemctl enable fancontrol.service
