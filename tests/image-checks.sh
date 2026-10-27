#!/usr/bin/env bash
# Controlli dentro l'immagine costruita (CI) o sul NAS installato.
# Uso: podman run --rm <image> bash /usr/share/nas-os/tests/image-checks.sh
set -u
source "$(dirname "$0")/lib.sh"

KVER=$(ls /usr/lib/modules | head -1)
KARGS=/usr/lib/bootc/kargs.d/10-nas.toml

section "Base"
check "Fedora 44" grep -q 'VERSION_ID=44' /etc/os-release
check "docker presente" bash -c 'rpm -q moby-engine || rpm -q docker-ce'
check "timer bootc update spento" ! systemctl is-enabled bootc-fetch-apply-updates.timer
check "timer rpm-ostree automatico spento" ! systemctl is-enabled rpm-ostreed-automatic.timer
check "zincati spento" ! systemctl is-enabled zincati.service
check "build info" test -s /usr/share/nas-os/build-info

section "Firma"
check "chiave pubblica nas-os" test -s /etc/pki/containers/nas-os.pub
check "policy firma nas-os" jq -e '.transports.docker["ghcr.io/drdamnation/nas-os"][0].type == "sigstoreSigned"' /etc/containers/policy.json
check "sigstore attachments nas-os" grep -q 'ghcr.io/drdamnation/nas-os' /etc/containers/registries.d/nas-os.yaml

section "Driver Asustor"
for mod in asustor asustor_it87 asustor_gpio_it87; do
    check "$mod per il kernel dell'immagine ($KVER)" modinfo -k "$KVER" "$mod"
    check "$mod caricato all'avvio" grep -qx "$mod" /usr/lib/modules-load.d/asustor.conf
done
check "niente kernel-devel rimasto" ! rpm -q kernel-devel
check "niente gcc rimasto" ! rpm -q gcc

section "Ventola e sensori"
check "karg acpi_enforce_resources=lax" grep -q 'acpi_enforce_resources=lax' "$KARGS"
check "lm_sensors" rpm -q lm_sensors
check "fancontrol presente" test -x /usr/sbin/fancontrol
check "fancontrol abilitato" systemctl is-enabled fancontrol.service
check "config ventola generata all'avvio" grep -q 'fancontrol-config /run/fancontrol' /usr/lib/systemd/system/fancontrol.service.d/10-nas.conf
check "senza hardware non scrive config" bash -c '! /usr/libexec/nas-os/fancontrol-config /tmp/fc-test && test ! -e /tmp/fc-test'

section "Dischi"
check "karg rd.md=0 (initramfs non assembla RAID)" grep -q 'rd.md=0' "$KARGS"
check "mdadm.conf: AUTO -all" grep -qx 'AUTO -all' /etc/mdadm.conf
check "mdadm.conf: nessun ARRAY nell'immagine" ! grep -q '^ARRAY' /etc/mdadm.conf
check "adotta-md1 eseguibile" test -x /usr/libexec/nas-os/adotta-md1
MNT=/usr/lib/systemd/system/var-mnt-dati.mount
check "mount dati da /dev/md/dati" grep -qx 'What=/dev/md/dati' "$MNT"
for opt in ro nofail x-systemd.device-timeout=10s; do
    check "mount dati con $opt" grep -Eq "^Options=(.*,)?${opt}(,|$)" "$MNT"
done
check "mount dati abilitato" systemctl is-enabled var-mnt-dati.mount
check "smartmontools" rpm -q smartmontools
check "smartd abilitato" systemctl is-enabled smartd.service
check "controllo RAID periodico" systemctl is-enabled raid-check.timer

section "Pannello"
check "cockpit-file-sharing" rpm -q cockpit-file-sharing
check "cockpit-identities" rpm -q cockpit-identities
check "cockpit-navigator" test -f /usr/share/cockpit/navigator/manifest.json
check "cockpit NON aperto a tutti" bash -c '! firewall-offline-cmd --zone=public --list-services | grep -qw cockpit'
check "cockpit solo da 4 reti fidate" bash -c "[ \$(firewall-offline-cmd --zone=public --list-rich-rules | grep -c 'service name=\"cockpit\" accept') = 4 ]"
for net in 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12 100.64.0.0/10; do
    check "cockpit da $net" bash -c "firewall-offline-cmd --zone=public --list-rich-rules | grep -q 'address=\"$net\"'"
done

finish
