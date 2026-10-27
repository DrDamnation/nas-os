#!/usr/bin/env bash
# Test di backup con rsync finto. Uso: bash tests/backup.sh
set -u
cd "$(dirname "$0")/.."
source tests/lib.sh
S=system_files/usr/libexec/nas-os/backup
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/foto" "$tmp/vault"
cat > "$tmp/rsync" <<'R'
#!/bin/sh
echo "$*" >> "$CHIAMATE"
R
chmod +x "$tmp/rsync"
conf() {  # $1 = comando di dump
cat > "$tmp/conf" <<C
DEST=utente@wd:/backup/nas
CHIAVE=$tmp/chiave
SORGENTI=("$tmp/foto" "$tmp/vault")
DUMP=("db1|$1")
C
}
esegui() { CHIAMATE="$tmp/chiamate" RSYNC="$tmp/rsync" DUMPDIR="$tmp/dump" bash "$S" "$tmp/conf" > "$tmp/out" 2>&1; }

section "tutto bene"
conf "echo SELECT 1"; rm -f "$tmp/chiamate"
check "riesce" esegui
check "dump scritto e compresso" bash -c "gzip -dc '$tmp/dump/db1.sql.gz' | grep -q 'SELECT 1'"
check "3 rsync (2 sorgenti + dump)" bash -c "[ \$(wc -l < '$tmp/chiamate') = 3 ]"
check "cestino datato sul WD" grep -q -- "--backup-dir=.cestino/$(date +%F)" "$tmp/chiamate"
check "cancellazioni solo verso il cestino" bash -c "grep -c -- '--delete' '$tmp/chiamate' | grep -qx 3 && ! grep -v -- '--backup ' '$tmp/chiamate'"
check "usa la chiave" grep -q -- "ssh -i $tmp/chiave" "$tmp/chiamate"
check "destinazione" grep -q 'utente@wd:/backup/nas/' "$tmp/chiamate"

section "dump fallito"
conf "false"; rm -f "$tmp/chiamate"
check "errore" ! esegui
check "nessun rsync" test ! -e "$tmp/chiamate"
check "nomina il dump" grep -q db1 "$tmp/out"
check "niente file dump a metà" test ! -e "$tmp/dump/db1.sql.gz.tmp"

section "conf mancante"
rm -f "$tmp/chiamate"
check "errore" ! env CHIAMATE="$tmp/chiamate" RSYNC="$tmp/rsync" bash "$S" "$tmp/manca"
check "nessun rsync" test ! -e "$tmp/chiamate"

section "rsync fallito al primo"
conf "echo ok"; printf '#!/bin/sh\necho "$*" >> "$CHIAMATE"; exit 23\n' > "$tmp/rsync"
rm -f "$tmp/chiamate"
check "errore" ! esegui
check "si ferma al primo" bash -c "[ \$(wc -l < '$tmp/chiamate') = 1 ]"

finish
