#!/usr/bin/env bash
# Test di avvia-stack con docker e /proc/mounts finti. Uso: bash tests/avvia-stack.sh
set -u
cd "$(dirname "$0")/.."
source tests/lib.sh
S=system_files/usr/libexec/nas-os/avvia-stack
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/uno" "$tmp/rotto" "$tmp/tre"
# docker finto: registra la cartella, fallisce in "rotto"
cat > "$tmp/docker" <<D
#!/bin/sh
echo "\$PWD \$*" >> "$tmp/chiamate"
case "\$PWD" in */rotto) exit 1;; esac
D
chmod +x "$tmp/docker"
printf '# commento\n\n%s\n%s\n%s\n' "$tmp/uno" "$tmp/rotto" "$tmp/tre" > "$tmp/conf"
monta() { echo "/dev/md127 /var/mnt/dati ext4 $1,noatime 0 0" > "$tmp/mounts"; }
esegui() { DOCKER="$tmp/docker" MOUNTS="$tmp/mounts" DATI=/var/mnt/dati bash "$S" "$tmp/conf" > "$tmp/out" 2>&1; }

section "dati in lettura/scrittura"
monta rw; rm -f "$tmp/chiamate"
check "esce con errore se uno fallisce" ! esegui
check "il terzo parte anche se il secondo è rotto" grep -q "$tmp/tre compose up -d" "$tmp/chiamate"
check "tre tentativi" bash -c "[ \$(wc -l < '$tmp/chiamate') = 3 ]"
check "riepilogo" grep -q 'OK 2 / FALLITI 1' "$tmp/out"
check "nomina lo stack rotto" grep -q "rotto" "$tmp/out"

section "dati in sola lettura"
monta ro; rm -f "$tmp/chiamate"
check "esce senza errore" esegui
check "non chiama docker" test ! -e "$tmp/chiamate"
check "lo dice" grep -qi "sola lettura" "$tmp/out"

section "dati non montati"
: > "$tmp/mounts"; rm -f "$tmp/chiamate"
check "esce senza errore" esegui
check "non chiama docker" test ! -e "$tmp/chiamate"

section "cartella inesistente"
monta rw; rm -f "$tmp/chiamate"; printf '%s\n%s\n' "$tmp/manca" "$tmp/uno" > "$tmp/conf"
check "errore" ! esegui
check "conta come fallita" grep -q 'OK 1 / FALLITI 1' "$tmp/out"

finish
