#!/bin/bash
# Ultimo step: niente aggiornamenti automatici, info build, pulizia.
source "$(dirname "$0")/vars.sh"

# Aggiornamento solo manuale: bootc upgrade + riavvio
systemctl disable bootc-fetch-apply-updates.timer rpm-ostreed-automatic.timer || true
systemctl mask zincati.service || true

cat > /usr/share/nas-os/build-info <<INFO
image=ghcr.io/drdamnation/nas-os
built=$(date -u +%Y-%m-%dT%H:%M:%SZ)
commit=${GIT_SHA:-unknown}
kernel=${KVER}
INFO

dnf5 clean all
