#!/bin/bash
# Unico step che tocca kernel e moduli: driver piattaforma Asustor (LED, pulsanti, ventola, sensori).
source "$(dirname "$0")/vars.sh"

devel="/tmp/kernel-rpms/kernel-devel-${KVER}.rpm"
if [[ ! -f $devel ]]; then
    echo "ERRORE: akmods non ha kernel-devel per il kernel di uCore (${KVER}):" >&2
    ls /tmp/kernel-rpms >&2
    exit 1
fi
dnf5 install -y gcc make "$devel"

src=$(mktemp -d)
curl -fsSL -o "$src/drv.tgz" \
    "https://github.com/DrDamnation/asustor-platform-driver/archive/${ASUSTOR_DRIVER_COMMIT}.tar.gz"
echo "${ASUSTOR_DRIVER_SHA256}  $src/drv.tgz" | sha256sum -c -
tar -xzf "$src/drv.tgz" -C "$src"
dir="$src/asustor-platform-driver-${ASUSTOR_DRIVER_COMMIT}"
make -C "/usr/src/kernels/${KVER}" M="$dir" modules
for mod in asustor asustor_it87 asustor_gpio_it87; do
    install -Dm644 "$dir/${mod}.ko" "/usr/lib/modules/${KVER}/extra/asustor/${mod}.ko"
done
depmod -a "$KVER"
for mod in asustor asustor_it87 asustor_gpio_it87; do
    modinfo -k "$KVER" "$mod" >/dev/null
done
rm -rf "$src"
dnf5 remove -y gcc make kernel-devel
