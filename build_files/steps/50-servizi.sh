#!/bin/bash
# Servizi: percorsi di ADM, Docker, Tailscale, avvio degli stack, Samba, backup.
source "$(dirname "$0")/vars.sh"

# I compose di ADM usano /volume1/... e /share/...: puntano entrambi al RAID dei dati
ln -sfn var/mnt/dati /volume1
ln -sfn var/mnt/dati /share
# Certificato di ADM citato da alcuni compose: /usr è di sola lettura, il contenuto sta in /var
mkdir -p /usr/builtin/etc
ln -sfn /var/lib/nas-os/adm-certificate /usr/builtin/etc/certificate

systemctl enable docker.service tailscaled.service

# Tailscale come la LAN: interfaccia nella zona fidata
firewall-offline-cmd --zone=trusted --add-interface=tailscale0
# Porta WireGuard di Tailscale: senza, solo collegamenti via relay DERP
firewall-offline-cmd --zone=public --add-port=41641/udp

# Stack Docker: elenco in /etc/nas-os/stacks.conf (dal repo privato nas-stacks)
chmod 755 /usr/libexec/nas-os/avvia-stack
systemctl enable nas-stacks.service

# Migrazione da ADM (lanciati a mano dopo l'installazione)
chmod 755 /usr/libexec/nas-os/migra-volumi /usr/libexec/nas-os/adotta-tailscale /usr/libexec/nas-os/dati-in-scrittura

# Samba: condivisioni nel registro (Cockpit), solo dalle reti fidate
dnf5 install -y --setopt=install_weak_deps=False samba
systemctl enable smb.service
firewall-offline-cmd --zone=public --remove-service=samba || true
for net in $RETI_FIDATE; do
    firewall-offline-cmd --zone=public \
        --add-rich-rule="rule family=ipv4 source address=${net} service name=samba accept"
done

# Backup notturno sul WD + avviso Telegram se fallisce. Segreti in /var/lib/nas-os/secrets (0700).
chmod 755 /usr/libexec/nas-os/backup /usr/libexec/nas-os/avviso
systemctl enable nas-backup.timer

echo 'd /var/lib/nas-os/secrets 0700 root root -' > /usr/lib/tmpfiles.d/nas-os.conf

# Copia oraria dell'NVMe veloce sul RAID
chmod 755 /usr/libexec/nas-os/copia-nvme
systemctl enable nas-copia-nvme.timer
