#!/usr/bin/env bash
# Test di adotta-md1 con un mdadm finto. Uso: bash tests/adotta-md1.sh
set -u
cd "$(dirname "$0")/.."
source tests/lib.sh
S=system_files/usr/libexec/nas-os/adotta-md1
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

finto() {  # $1 = file con l'output da simulare
    printf '#!/bin/sh\ncat %q\n' "$1" > "$tmp/mdadm"; chmod +x "$tmp/mdadm"
}
nuova_conf() { printf 'AUTO -all\n' > "$tmp/conf"; }
esegui() { MDADM="$tmp/mdadm" MDADM_CONF="$tmp/conf" bash "$S"; }

cat > "$tmp/tre" <<'OUT'
ARRAY /dev/md/0  metadata=1.2 UUID=aaaaaaaa:aaaaaaaa:aaaaaaaa:aaaaaaaa name=AS6702T:0
   devices=/dev/sda2,/dev/sdb2
ARRAY /dev/md/126  metadata=1.2 UUID=bbbbbbbb:bbbbbbbb:bbbbbbbb:bbbbbbbb name=AS6702T:126
   devices=/dev/sda3,/dev/sdb3
ARRAY /dev/md/1  metadata=1.2 UUID=cccccccc:cccccccc:cccccccc:cccccccc name=AS6702T:1
   devices=/dev/sda4,/dev/sdb4
OUT
section "tre array ADM"
finto "$tmp/tre"; nuova_conf
check "riesce" esegui
check "scrive md1" grep -qx 'ARRAY /dev/md/dati metadata=1.2 UUID=cccccccc:cccccccc:cccccccc:cccccccc' "$tmp/conf"
check "una sola riga ARRAY" bash -c "[ \$(grep -c '^ARRAY' '$tmp/conf') = 1 ]"
check "AUTO -all resta" grep -qx 'AUTO -all' "$tmp/conf"
check "seconda volta rifiuta" ! esegui

section "due candidati"
{ cat "$tmp/tre"; printf 'ARRAY /dev/md/9 metadata=1.2 UUID=dddddddd:dddddddd:dddddddd:dddddddd\n   devices=/dev/sdc4,/dev/sdd4\n'; } > "$tmp/due"
finto "$tmp/due"; nuova_conf
check "rifiuta" ! esegui
check "non scrive" ! grep -q '^ARRAY' "$tmp/conf"

section "nessun candidato"
head -4 "$tmp/tre" > "$tmp/zero"
finto "$tmp/zero"; nuova_conf
check "rifiuta" ! esegui
check "non scrive" ! grep -q '^ARRAY' "$tmp/conf"

section "partizione mista"
printf 'ARRAY /dev/md/1 metadata=1.2 UUID=eeeeeeee:eeeeeeee:eeeeeeee:eeeeeeee\n   devices=/dev/sda4,/dev/nvme0n1p4\n' > "$tmp/misto"
finto "$tmp/misto"; nuova_conf
check "rifiuta" ! esegui

finish
