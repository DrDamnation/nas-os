# nas-os

Immagine bootc per un Asustor AS6702T (Lockerstor 2 Gen2) al posto di ADM: Fedora CoreOS 44
(base Universal Blue `ucore:stable`) con Docker, Cockpit + moduli 45Drives, Samba, NFS, Tailscale
e il driver piattaforma Asustor (LED, ventola, sensori).

- Immagine: `ghcr.io/drdamnation/nas-os:stable` (firmata con cosign, chiave in `cosign.pub`)
- Progetto: [`docs/superpowers/specs/2026-10-27-nas-os-design.md`](docs/superpowers/specs/2026-10-27-nas-os-design.md)
- Piano: [`docs/superpowers/plans/2026-10-27-nas-os-image.md`](docs/superpowers/plans/2026-10-27-nas-os-image.md)

## Struttura

- `build_files/build.sh` copia `system_files/` su `/` ed esegue `build_files/steps/NN-*.sh` in ordine.
- `tests/image-checks.sh` gira in CI dentro l'immagine appena costruita (e sul NAS installato).
- `tests/secrets-scan.sh` blocca segreti e dati personali (hook pre-commit: `git config core.hooksPath .githooks`).

## Dischi

Nessun RAID si assembla da solo (`AUTO -all`, `rd.md=0`): gli array di sistema di ADM restano intatti.
Il RAID dei dati si adotta a mano con `sudo /usr/libexec/nas-os/adotta-md1` e si monta in sola
lettura su `/var/mnt/dati`.

## Aggiornare

Gli aggiornamenti automatici sono spenti: `sudo bootc upgrade` e riavvio.
Per tornare indietro: `sudo bootc rollback` e riavvio.
