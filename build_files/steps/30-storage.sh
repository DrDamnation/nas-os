#!/bin/bash
# Dischi: nessun RAID automatico, dati di ADM solo in lettura, SMART e controllo RAID periodico.
source "$(dirname "$0")/vars.sh"

dnf5 install -y mdadm smartmontools
chmod 755 /usr/libexec/nas-os/adotta-md1
chmod 644 /etc/mdadm.conf
systemctl enable var-mnt-dati.mount smartd.service raid-check.timer
