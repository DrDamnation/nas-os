#!/usr/bin/env bash
# Esegue il %post del kickstart dentro l'immagine vera (senza bootc switch) e verifica
# che alla fine si possa entrare: daniele (uid 1003, wheel) e root con la chiave SSH.
set -euo pipefail
cd "$(dirname "$0")/.."
IMG="${1:?uso: iso-post-prova.sh <immagine>}"
post=$(python3 - <<'PY'
import tomllib,re
k=tomllib.load(open('disk_config/iso-nas.toml','rb'))['customizations']['installer']['kickstart']['contents']
p=re.search(r'%post[^\n]*\n(.*?)%end',k,re.S).group(1)
print('\n'.join(l for l in p.splitlines() if not l.startswith('bootc switch')))
PY
)
sudo podman run --rm -i "$IMG" bash -s <<SCRIPT
echo "== gruppi in /etc/group prima:"; grep -E '^(wheel|users):' /etc/group || echo "(nessuno: stanno in /usr/lib/group)"
mkdir -p /var/home /var/roothome
$post
echo "== verifica"
set -e
id daniele
[ "\$(id -u daniele)" = 1003 ]
id -nG daniele | grep -qw wheel
test -s /var/home/daniele/.ssh/authorized_keys
[ "\$(stat -c %U /var/home/daniele/.ssh/authorized_keys)" = daniele ]
test -s /var/roothome/.ssh/authorized_keys
test -s /etc/sudoers.d/90-daniele
echo "PROVA %post: OK"
SCRIPT
