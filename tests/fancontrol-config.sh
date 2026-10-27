#!/usr/bin/env bash
# Test di fancontrol-config su un sysfs finto. Uso: bash tests/fancontrol-config.sh
set -u
cd "$(dirname "$0")/.."
source tests/lib.sh
S=system_files/usr/libexec/nas-os/fancontrol-config
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
sys=$tmp/sys; mkdir -p "$sys/class/hwmon" "$sys/devices/platform/asustor_it87.656/hwmon/hwmon3" "$sys/devices/platform/coretemp.0/hwmon/hwmon1"
it=$sys/devices/platform/asustor_it87.656/hwmon/hwmon3; ct=$sys/devices/platform/coretemp.0/hwmon/hwmon1
echo it8625 > "$it/name"; touch "$it/pwm1" "$it/fan1_input"; ln -s ../.. "$it/device"
echo coretemp > "$ct/name"; touch "$ct/temp1_input"; ln -s ../.. "$ct/device"
ln -s "$it" "$sys/class/hwmon/hwmon3"; ln -s "$ct" "$sys/class/hwmon/hwmon1"

section "hardware presente"
check "riesce" env SYS_ROOT="$sys" bash "$S" "$tmp/out"
check "ventola su pwm1 di hwmon3" grep -qx 'FCTEMPS=hwmon3/pwm1=hwmon1/temp1_input' "$tmp/out"
check "percorso relativo a /sys" grep -q 'DEVPATH=hwmon3=devices/platform/asustor_it87.656 hwmon1=devices/platform/coretemp.0' "$tmp/out"
check "nome del chip" grep -q 'DEVNAME=hwmon3=it8625 hwmon1=coretemp' "$tmp/out"
check "minimo 80 (mai ferma)" grep -qx 'MINPWM=hwmon3/pwm1=80' "$tmp/out"

section "hardware assente (CI, driver non caricato)"
mkdir -p "$tmp/vuoto"
check "esce con errore" ! env SYS_ROOT="$tmp/vuoto" bash "$S" "$tmp/out2"
check "non scrive" test ! -e "$tmp/out2"

finish
