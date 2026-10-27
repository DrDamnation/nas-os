# nas-os — sistema per il NAS Asustor AS6702T

Data: 2026-10-27. Stato: bozza da approvare.

## 1. Perché

Il NAS di Locorotondo gira ADM (Asustor). Il 26/10/2026 ADM ha smontato `/proc` al boot e durante
l'aggiornamento; Docker non partiva più, Paperless è rimasto giù ore e l'aggiornamento è fallito al 99%.
Prima ancora: radice in RAM che si azzera a ogni riavvio, Tailscale da tenere in vita con un container
privilegiato, `sudo` con password, `e2fsck` impossibile da remoto, app di App Central che si pestano i piedi.

Daniele usa il NAS quasi solo come host Docker (~40 container). Vuole un sistema come air-os: immagine
bootc costruita da un repo GitHub, riproducibile, con `rollback` se un aggiornamento va storto.

## 2. Obiettivi, non-obiettivi, anti-obiettivi

**Obiettivi**
- Immagine bootc `ghcr.io/drdamnation/nas-os:stable`, costruita in CI e firmata (come air-os).
- Hardware AS6702T pieno: LED, ventola regolata sulla temperatura, sensori, pulsanti.
- Pannello web per dischi, RAID, condivisioni Samba/NFS, utenti: Cockpit + moduli 45Drives.
- Tutti i servizi Docker attuali ripartono con gli stessi dati.
- Aggiornamenti solo manuali (`bootc upgrade` + riavvio), `bootc rollback` per tornare indietro.
- Reinstallazione = stesso NAS: tutta la configurazione sta nei repo, i segreti fuori.

**Non-obiettivi**
- Niente ZFS, niente riformattazione dei dischi: il RAID1 `md1` (ext4, 13 TB) resta com'è.
- Niente equivalente di App Central: tutto è container.
- Niente aggiornamenti automatici con riavvio.

**Anti-obiettivi (fallimento anche se "funziona")**
- Perdere o anche solo rischiare dati di `md1` durante la migrazione.
- Rendere impossibile tornare ad ADM.
- Segreti (token, password, `.env`) nel repo pubblico.
- Servizi raggiungibili da internet che oggi non lo sono.

## 3. Hardware (verificato il 26-27/10/2026)

| Cosa | Valore |
|---|---|
| Modello | Asustor AS6702T (Lockerstor 2 Gen2), DMI "Intel Corporation / Jasper Lake Client Platform" |
| CPU / GPU | Intel Celeron N5105, 4 core, iGPU Jasper Lake (QuickSync) |
| RAM | 20 GB |
| eMMC 8 GB (`mmcblk0`) | ADM 5.1.4.RM62 — **non si tocca**, è il ripiego |
| 2× HDD 14 TB (`sda`,`sdb`) | partizioni ADM: `md0` (sda2+sdb2, sistema ADM), `md126` (sda3+sdb3, swap ADM), `md1` (sda4+sdb4, RAID1 ext4 dati, 1,9 TB usati, flag "errori da controllare") |
| NVMe Crucial P1 500 GB (`nvme0n1`) | libero ("Inattivo" in ADM, nessun volume) → **disco di sistema di nas-os** |
| Rete | 2× 2,5 GbE |
| Driver piattaforma | `mafredri/asustor-platform-driver` supporta AS6702T: LED, pulsanti, `asustor-it87` (ventola pwm1, sensori). Ultimo commit 12/2025, compila su kernel ≥ 6.17 |

## 4. Decisioni prese

- **Base:** `ghcr.io/ublue-os/ucore:stable` (Fedora CoreOS). Ha già Cockpit (storage), Samba, NFS,
  Tailscale, Docker + Compose, mergerfs, rclone, firewalld; Zincati (aggiornamento automatico) spento.
  *(Daniele: bootc stile air-os. Base uCore: scelta mia.)*
- **Pannello:** Cockpit + `cockpit-file-sharing`, `cockpit-navigator`, `cockpit-identities` (45Drives, open source).
  OpenMediaVault non si porta: è legato a Debian (Salt, `.deb`, suo database). *(Daniele: "se è open source
  prendiamo il pannello, altrimenti lo ricreiamo" → non serve ricrearlo.)*
- **Driver Asustor:** fork in `DrDamnation/asustor-platform-driver`, compilato nell'immagine nello step
  `20-kernel-modules.sh` (come facetimehd in air-os); la build fallisce se il modulo non si carica sul kernel
  dell'immagine. Correzioni mandate anche a monte. *(Daniele.)*
- **Ventola:** `fancontrol` con config per AS6702T nell'immagine; senza config la ventola resta al valore BIOS.
- **Sistema sull'NVMe**, ADM resta sull'eMMC: per tornare indietro si cambia il disco d'avvio nel BIOS. *(Daniele.)*
- **Dati:** `md1` montato prima **in sola lettura**; si passa a lettura/scrittura solo dopo la verifica.
  `md0`/`md126` (sistema ADM) mai montati né modificati: `mdadm` configurato per non assemblarli.
- **Docker:** resta Docker (moby) con i compose attuali, non Podman: zero riscritture. Dati Docker
  (`/var/lib/docker`) e database sull'NVMe; media e archivi su `md1`.
- **Repo:** `nas-os` **pubblico** (immagine, come air-os: il NAS la scarica senza token),
  `nas-stacks` **privato** (compose e config dei servizi), `asustor-platform-driver` pubblico (copia del driver,
  remote `upstream` = mafredri). Segreti solo sul NAS in `/var/lib/nas-os/secrets` (0600). *(Daniele.)*
- **Controlli anti-dati-sensibili** (Daniele: "nel pubblico niente dati sensibili, metti dei controlli"):
  `tests/secrets-scan.sh` cerca per forma segreti (token, JWT, chiavi, password) e dati personali (email,
  codice fiscale, IBAN, telefoni); i valori personali specifici (IP pubblico, tailnet, email di famiglia)
  stanno in `.secrets-scan-extra` (escluso da git) e nel segreto CI `SECRETS_SCAN_EXTRA`, mai nel repo.
  Gira come hook pre-commit (`.githooks/`) e in CI insieme a gitleaks su tutto lo storico; stesso controllo
  nel repo del driver e su ogni patch mandata a monte.
- **Backup:** notturno verso il WD My Cloud EX2 Ultra (192.168.1.18, SSH con chiave): originali Immich,
  Vaultwarden, Paperless, dump dei database. *(Daniele: backup sul WD.)*
- **Nessun disco d'appoggio** per la migrazione. *(Daniele.)*

## 5. Architettura

```
GitHub nas-os ──CI──► ghcr.io/drdamnation/nas-os:stable (firmata cosign)
                                   │ bootc upgrade (manuale)
NAS AS6702T: NVMe = nas-os  ── md1 (RAID1 ext4, dati) ── /var/mnt/dati
              eMMC = ADM (ripiego)
GitHub nas-stacks (privato) ──git pull──► /var/lib/nas-os/stacks/<servizio>/compose.yaml
```

Struttura del repo identica ad air-os: `Containerfile`, `build_files/build.sh` + `build_files/steps/NN-*.sh`,
`system_files/` copiati su `/`, `disk_config/` per l'ISO d'installazione, `tests/image-checks.sh` in CI.

## 6. Contenuto dell'immagine

1. **10-signing** — policy cosign per `ghcr.io/drdamnation/nas-os`.
2. **20-kernel-modules** — `asustor`, `asustor-it87`, `asustor-gpio-it87` dal fork, verificati con `modinfo`.
3. **25-asustor-hardware** — `fancontrol` + config, `lm_sensors`, regole LED (stato disco, rete), kargs
   `acpi_enforce_resources=lax` se il driver lo richiede.
4. **30-storage** — `mdadm.conf` che assembla solo `md1` (per UUID) e ignora `md0`/`md126`; unit di mount
   `md1` (prima `ro`), `smartd` con avvisi, check periodico RAID.
5. **40-cockpit** — moduli 45Drives; Cockpit solo su LAN e Tailscale (firewalld).
6. **50-servizi** — Docker abilitato, unit `nas-stacks.service` che fa `git pull` e `docker compose up -d`
   per ogni stack; Tailscale con stato in `/var/lib/tailscale` (persistente).
7. **60-backup** — timer notturno verso il WD + avviso se fallisce (Telegram via TelegramNotifier).
8. **90-finalize** — pulizia, `bootc container lint`.

## 7. Installazione (serve qualcuno davanti al NAS)

1. ISO nas-os (da `disk_config/`) su chiavetta USB con Rufus.
2. Schermo HDMI + tastiera; BIOS → avvio da USB; destinazione **solo l'NVMe Crucial**.
3. Primo avvio da remoto (Tailscale): verifica sensori/ventola/LED, assemblaggio `md1` in sola lettura,
   controllo dati (conteggio file e dimensioni contro l'inventario fatto da ADM prima della migrazione).
4. `e2fsck` su `md1` (smontato), poi montaggio in lettura/scrittura.
5. Migrazione servizi a gruppi (prima Paperless e Vaultwarden, poi Immich, poi il resto).
6. ADM resta sull'eMMC finché tutto gira da almeno 2 settimane.

## 8. Lasciato al builder

- Formato esatto dell'ISO (bootc-image-builder anaconda-iso vs installer CoreOS + `bootc install`).
- Firma dei moduli per Secure Boot o Secure Boot spento sul NAS (da verificare nel BIOS).
- Mappatura UID/GID: i file su `md1` appartengono a utenti ADM (admin 999, daniele 1003, gruppo 100).
- Ordine di migrazione dei singoli container e loro healthcheck.

## 9. Da verificare sulla macchina

- Il driver carica sul kernel di uCore stable e `pwm1` regola davvero la ventola dell'AS6702T.
- `md1` si assembla da solo con `mdadm` standard (superblock 1.2) senza toccare `md0`/`md126`.
- La iGPU è vista da Immich (QuickSync) come su ADM.
- Il BIOS permette avvio da NVMe (l'AS6702T lo prevede per l'NVMe nello slot M.2).
