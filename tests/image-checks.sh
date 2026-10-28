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
check "niente toolchain C++" ! rpm -q gcc-c++

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

section "Installazione"
check "radice xfs dichiarata per l'installer" grep -qx 'type = "xfs"' /usr/lib/bootc/install/00-nas-os.toml

section "Servizi"
check "/volume1 punta ai dati" bash -c '[ "$(readlink /volume1)" = var/mnt/dati ]'
check "/share punta ai dati" bash -c '[ "$(readlink /share)" = var/mnt/dati ]'
check "stub DNS spento (porta 53 per Pi-hole)" grep -qx 'DNSStubListener=no' /usr/lib/systemd/resolved.conf.d/10-nas.conf
check "docker abilitato" systemctl is-enabled docker.service
check "tailscaled abilitato" systemctl is-enabled tailscaled.service
check "nas-stacks abilitato" systemctl is-enabled nas-stacks.service
check "stacks.conf senza stack (vengono dal repo privato)" bash -c '! grep -vE "^[[:space:]]*(#|$)" /etc/nas-os/stacks.conf'
check "certificato ADM letto da /var" bash -c '[ "$(readlink /usr/builtin/etc/certificate)" = /var/lib/nas-os/adm-certificate ]'
for s in avvia-stack migra-volumi adotta-tailscale dati-in-scrittura; do check "$s eseguibile" test -x /usr/libexec/nas-os/$s; done
check "tailscale0 nella zona trusted" bash -c 'firewall-offline-cmd --zone=trusted --list-interfaces | grep -qw tailscale0'

section "Samba"
check "smb.conf valido" testparm -s --suppress-prompt /etc/samba/smb.conf
check "condivisioni dal registro (Cockpit)" grep -q 'include = registry' /etc/samba/smb.conf
check "solo reti fidate" grep -q 'hosts allow = 127.0.0.1 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12 100.64.0.0/10' /etc/samba/smb.conf
check "niente ospiti" grep -q 'map to guest = never' /etc/samba/smb.conf
check "smb abilitato" systemctl is-enabled smb.service
check "samba NON aperto a tutti" bash -c '! firewall-offline-cmd --zone=public --list-services | grep -qw samba'
check "samba da 4 reti fidate" bash -c "[ \$(firewall-offline-cmd --zone=public --list-rich-rules | grep -c 'service name=\"samba\" accept') = 4 ]"

section "Backup"
check "timer backup abilitato" systemctl is-enabled nas-backup.timer
check "backup alle 03:30" grep -q 'OnCalendar=\*-\*-\* 03:30:00' /usr/lib/systemd/system/nas-backup.timer
check "avviso se fallisce" grep -q 'OnFailure=nas-avviso@%n.service' /usr/lib/systemd/system/nas-backup.service
for s in backup avviso; do check "$s eseguibile" test -x /usr/libexec/nas-os/$s; done
check "cartella segreti 0700" grep -q '^d /var/lib/nas-os/secrets 0700 root root' /usr/lib/tmpfiles.d/nas-os.conf
check "backup.conf solo esempio" bash -c '! grep -vE "^[[:space:]]*(#|$)" /etc/nas-os/backup.conf'
check "jq e curl per l'avviso" bash -c 'command -v jq && command -v curl'

section "Docker e NVMe"
check "controllo chiavi Ignition spento" bash -c '[ "$(systemctl is-enabled coreos-check-ssh-keys.service 2>&1)" = masked ]'
check "docker senza --selinux-enabled" bash -c "! systemctl cat docker.service | grep -E '^ExecStart=.+' | tail -1 | grep -q selinux-enabled"
check "dati docker sulla partizione grande" grep -q '"data-root": "/var/home/docker"' /etc/docker/daemon.json
check "log docker limitati" grep -q '"max-size": "20m"' /etc/docker/daemon.json
check "copia-nvme eseguibile" test -x /usr/libexec/nas-os/copia-nvme
check "copia-nvme ogni ora" grep -q 'OnCalendar=hourly' /usr/lib/systemd/system/nas-copia-nvme.timer
check "porta Tailscale aperta" bash -c "firewall-offline-cmd --zone=public --list-ports | grep -qw 41641/udp"
check "adotta-tailscale sistema proprietario ed etichette" grep -q 'restorecon -R "\$dst"' /usr/libexec/nas-os/adotta-tailscale

section "Primo avvio (preset-all, come fa systemd al primo boot)"
systemctl preset-all >/dev/null 2>&1 || true
for u in nas-copia-nvme.timer fancontrol.service var-mnt-dati.mount smartd.service raid-check.timer docker.service tailscaled.service nas-stacks.service smb.service nas-backup.timer cockpit.service; do
    check "$u resta abilitato dopo preset-all" systemctl is-enabled "$u"
done
check "fancontrol non salta senza /etc/fancontrol" grep -qx 'ConditionFileNotEmpty=' /usr/lib/systemd/system/fancontrol.service.d/10-nas.conf

finish
