#!/usr/bin/env bash
# Test di migra-volumi con docker finto. Uso: bash tests/migra-volumi.sh
set -u
cd "$(dirname "$0")/.."
source tests/lib.sh
S=system_files/usr/libexec/nas-os/migra-volumi
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
old=$tmp/vecchio; new=$tmp/nuovo
mkdir -p "$old/volumes/dati/_data/sotto" "$old/volumes/vuoto/_data" "$new"
echo segreto > "$old/volumes/dati/_data/sotto/file"; chmod 600 "$old/volumes/dati/_data/sotto/file"
# docker finto: "volume create X" crea $new/X/_data, "volume inspect -f ... X" stampa il percorso
cat > "$tmp/docker" <<'D'
#!/bin/sh
for v; do :; done   # v = ultimo argomento
case "$1 $2" in
  "volume create") mkdir -p "$NUOVO/$v/_data"; echo "$v";;
  "volume inspect") [ -d "$NUOVO/$v" ] || exit 1; echo "$NUOVO/$v/_data";;
esac
D
chmod +x "$tmp/docker"
esegui() { NUOVO="$new" DOCKER="$tmp/docker" bash "$S" "$old" "$@" > "$tmp/out" 2>&1; }

section "volume da copiare"
check "riesce" esegui dati
check "contenuto copiato" grep -qx segreto "$new/dati/_data/sotto/file"
check "permessi conservati" bash -c "[ \$(stat -c %a '$new/dati/_data/sotto/file') = 600 ]"

section "volume nuovo già pieno"
check "rifiuta" ! esegui dati
check "dice perché" grep -qi "non è vuoto" "$tmp/out"

section "volume sorgente assente"
check "errore" ! esegui manca
check "lo nomina" grep -q manca "$tmp/out"

section "volume vuoto"
check "riesce" esegui vuoto

finish
