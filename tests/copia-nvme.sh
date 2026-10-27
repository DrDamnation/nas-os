#!/usr/bin/env bash
# Test di copia-nvme con findmnt finto. Uso: bash tests/copia-nvme.sh
set -u
cd "$(dirname "$0")/.."
source tests/lib.sh
S=system_files/usr/libexec/nas-os/copia-nvme
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/veloce/HA/config" "$tmp/dati"
echo ciao > "$tmp/veloce/HA/config/conf.yaml"
printf '#!/bin/sh\necho "$OPZ"\n' > "$tmp/findmnt"; chmod +x "$tmp/findmnt"
conf() { printf 'DUMP=("db1|%s")\n' "$1" > "$tmp/conf"; }
esegui() { OPZ=$1 VELOCE="$tmp/veloce" COPIA="$tmp/dati/.nvme-copia" DATI="$tmp/dati" FINDMNT="$tmp/findmnt" bash "$S" "$tmp/conf" > "$tmp/out" 2>&1; }

section "tutto bene"
conf "echo SELECT 1"
check "riesce" esegui rw,noatime
check "dump compresso sul RAID" bash -c "gzip -dc '$tmp/dati/.nvme-copia/dump/db1.sql.gz' | grep -q 'SELECT 1'"
check "cartelle copiate" grep -q ciao "$tmp/dati/.nvme-copia/file/HA/config/conf.yaml"
check "segna l'ora" test -s "$tmp/dati/.nvme-copia/ultima-copia"

section "dump fallito"
conf "echo mezzo; false"
check "errore" ! esegui rw
check "tiene il dump precedente" bash -c "gzip -dc '$tmp/dati/.nvme-copia/dump/db1.sql.gz' | grep -q 'SELECT 1'"
check "niente file a metà" test ! -e "$tmp/dati/.nvme-copia/dump/db1.sql.gz.tmp"
check "copia comunque le cartelle" grep -q ciao "$tmp/dati/.nvme-copia/file/HA/config/conf.yaml"
check "nomina il dump" grep -q db1 "$tmp/out"

section "RAID non scrivibile"
rm -rf "$tmp/dati/.nvme-copia"; conf "echo SELECT 1"
check "si rifiuta in sola lettura" ! esegui ro,noatime
check "non scrive nulla" test ! -e "$tmp/dati/.nvme-copia"
check "spiega" grep -q "sola lettura" "$tmp/out"

finish
