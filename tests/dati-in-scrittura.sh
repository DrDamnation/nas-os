#!/bin/bash
# Test di dati-in-scrittura con e2fsck e systemctl finti.
set -u
cd "$(dirname "$0")/.."
source tests/lib.sh
S=system_files/usr/libexec/nas-os/dati-in-scrittura

prova() {  # $1 = codice di uscita di e2fsck finto
    t=$(mktemp -d); touch "$t/md"
    printf '#!/bin/sh\necho "e2fsck $*" >> %s/log\nexit %s\n' "$t" "$1" > "$t/e2fsck"
    printf '#!/bin/sh\necho "systemctl $*" >> %s/log\n' "$t" > "$t/systemctl"
    chmod +x "$t/e2fsck" "$t/systemctl"
    DEV=$t/md DROPIN=$t/d/rw.conf E2FSCK=$t/e2fsck SYSTEMCTL=$t/systemctl bash "$S" > "$t/out" 2>&1; rc=$?
}

section "Pulito"
prova 0
check "esce 0" test "$rc" = 0
check "ferma stack e mount prima del controllo" bash -c "head -1 $t/log | grep -q 'systemctl stop nas-stacks.service var-mnt-dati.mount'"
check "e2fsck forzato e solo correzioni sicure" grep -q "e2fsck -f -p $t/md" "$t/log"
check "drop-in rw" grep -qx 'Options=rw,noatime,nofail,x-systemd.device-timeout=10s' "$t/d/rw.conf"
check "ricarica e rimonta" bash -c "tail -2 $t/log | tr '\n' ' ' | grep -q 'systemctl daemon-reload systemctl start var-mnt-dati.mount'"
DEV=$t/md DROPIN=$t/d/rw.conf E2FSCK=false SYSTEMCTL=false bash "$S" >/dev/null 2>&1; rc2=$?
check "seconda volta: non rifà nulla" test "$rc2" = 0
rm -rf "$t"

section "Errori corretti"
prova 1
check "esce 0 e scrive il drop-in" bash -c "[ $rc = 0 ] && [ -f $t/d/rw.conf ]"
rm -rf "$t"

section "Errori rimasti"
prova 4
check "esce 1" test "$rc" = 1
check "nessun drop-in" test ! -e "$t/d/rw.conf"
check "rimonta com'era (sola lettura)" bash -c "tail -1 $t/log | grep -qx 'systemctl start var-mnt-dati.mount'"
check "niente daemon-reload" ! grep -q daemon-reload "$t/log"
check "spiega cosa fare" grep -q 'e2fsck -f' "$t/out"
rm -rf "$t"

section "Senza RAID"
t=$(mktemp -d)
DEV=$t/manca DROPIN=$t/d/rw.conf E2FSCK=false SYSTEMCTL=false bash "$S" > "$t/out" 2>&1; rc=$?
check "esce 1 e indica adotta-md1" bash -c "[ $rc = 1 ] && grep -q adotta-md1 $t/out"
rm -rf "$t"

finish
