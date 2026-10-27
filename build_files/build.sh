#!/bin/bash
# Copia i file di sistema e i test, poi esegue gli step in ordine (NN-nome.sh).
set -ouex pipefail

cp -avf /ctx/system_files/. /

install -Dm644 -t /usr/share/nas-os/tests /ctx/tests/lib.sh /ctx/tests/image-checks.sh

for step in /ctx/steps/[0-9][0-9]-*.sh; do
    echo "::group::${step##*/}"
    bash "$step"
    echo "::endgroup::"
done
