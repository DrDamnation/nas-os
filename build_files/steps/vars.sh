# Variabili condivise dagli step. Ogni step fa: source "$(dirname "$0")/vars.sh"
set -ouex pipefail

FEDORA_VERSION=44
KVER=$(ls /usr/lib/modules | head -1)

# Driver piattaforma Asustor: nostra copia di mafredri/asustor-platform-driver, commit fissato
ASUSTOR_DRIVER_COMMIT=394a6486c238cd4f25069205b39b039addd5bd36
ASUSTOR_DRIVER_SHA256=23c3ce1b41547dacc6483b560bf6ea4d43a8fd8d3769357cf6b648dd38ed1761

# Moduli Cockpit di 45Drives (open source). Navigator 0.5.14 non ha RPM: si copia dal sorgente.
FILE_SHARING_VERSION=4.6.3
FILE_SHARING_SHA256=e095634d46d0487a8c3445e4fb11360bc6ddf4ac054e9a8b370cda19c552b2d1
IDENTITIES_VERSION=0.1.14-1
IDENTITIES_SHA256=75e7d5f80460233a03f3722b80b04ec1a294b9fbd4b4e9b2e3e991e2b5615cf1
NAVIGATOR_VERSION=0.5.14-1
NAVIGATOR_SHA256=d53825143edc7bfc57c7d0d1a0afca7404f98413b3c4ee499698e0010c5cd434

# Reti da cui il pannello è raggiungibile: LAN private e Tailscale
RETI_FIDATE="192.168.0.0/16 10.0.0.0/8 172.16.0.0/12 100.64.0.0/10"
