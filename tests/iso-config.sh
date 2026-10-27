#!/usr/bin/env bash
# Controlli statici sul kickstart dell'ISO: deve toccare SOLO l'NVMe e solo sull'Asustor.
set -u
cd "$(dirname "$0")/.."
source tests/lib.sh
K=disk_config/iso-nas.toml

section "Disco"
check "vede solo nvme0n1" grep -qx 'ignoredisk --only-use=nvme0n1' "$K"
check "cancella solo nvme0n1" grep -qx 'clearpart --all --initlabel --drives=nvme0n1 --disklabel=gpt' "$K"
check "nessun riferimento a sd*/mmcblk/md" ! grep -Eq '\b(sd[a-z]|mmcblk[0-9]|md[0-9]+)\b' "$K"

section "Macchina giusta"
check "pre-controllo che blocca l'installazione" grep -q '%pre --erroronfail' "$K"
check "controlla il modello dell'NVMe" grep -q '"CT500P1SSD8"' "$K"
check "controlla la scheda Asustor" grep -q '"Jasper Lake Client Platform"' "$K"

section "Accesso senza segreti"
check "chiave SSH pubblica" grep -Eq 'sshkey --username=daniele "ssh-ed25519 [A-Za-z0-9+/=]+"' "$K"
check "nessuna chiave privata" ! grep -q 'PRIVATE' "$K"
check "daniele con lo uid dei file sui dischi (1003)" grep -Eq '^user --name=daniele --uid=1003 --groups=wheel,users' "$K"
check "password di root bloccata" grep -qx 'rootpw --lock' "$K"
check "nessuna password in chiaro" ! grep -Eq -- '--(plaintext|password|iscrypted)' "$K"
check "segue l'immagine firmata" grep -q 'bootc switch --mutate-in-place --enforce-container-sigpolicy --transport registry ghcr.io/drdamnation/nas-os:stable' "$K"

section "TOML"
py=""
for p in python3 python; do "$p" -c 'import tomllib' 2>/dev/null && { py=$p; break; }; done
check "si legge come TOML" "${py:-python3}" -c "import tomllib; tomllib.load(open('$K','rb'))"

finish
