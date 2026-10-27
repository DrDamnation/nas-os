#!/bin/bash
# Pannello web: Cockpit di uCore + moduli 45Drives (condivisioni, utenti, file).
# Raggiungibile solo da LAN private e Tailscale.
source "$(dirname "$0")/vars.sh"

gh=https://github.com/45Drives
d=$(mktemp -d)
scarica() {  # url sha256 file
    curl -fsSL -o "$d/$3" "$1"
    echo "$2  $d/$3" | sha256sum -c -
}
scarica "$gh/cockpit-file-sharing/releases/download/v${FILE_SHARING_VERSION}/cockpit-file-sharing-${FILE_SHARING_VERSION}-1.el9.noarch.rpm" \
    "$FILE_SHARING_SHA256" file-sharing.rpm
scarica "$gh/cockpit-identities/releases/download/v${IDENTITIES_VERSION}/cockpit-identities-${IDENTITIES_VERSION}.el9.noarch.rpm" \
    "$IDENTITIES_SHA256" identities.rpm
scarica "$gh/cockpit-navigator/archive/refs/tags/v${NAVIGATOR_VERSION}.tar.gz" \
    "$NAVIGATOR_SHA256" navigator.tgz

dnf5 install -y firewalld "$d/file-sharing.rpm" "$d/identities.rpm"
tar -xzf "$d/navigator.tgz" -C "$d"
mkdir -p /usr/share/cockpit
cp -a "$d/cockpit-navigator-${NAVIGATOR_VERSION}/navigator" /usr/share/cockpit/navigator
rm -rf "$d"

# Cockpit mai aperto a tutti: solo dalle reti fidate
firewall-offline-cmd --zone=public --remove-service=cockpit || true
for net in $RETI_FIDATE; do
    firewall-offline-cmd --zone=public \
        --add-rich-rule="rule family=ipv4 source address=${net} service name=cockpit accept"
done
