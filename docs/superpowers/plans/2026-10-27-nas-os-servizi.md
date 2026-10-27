# nas-os, servizi, backup e chiavetta — piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** dalla prima immagine (piano `2026-10-27-nas-os-image.md`) a una chiavetta d'installazione pronta: servizi Docker che ripartono dai compose attuali, Tailscale con la stessa identità, condivisioni Samba, backup notturno sul WD, ISO che installa solo sull'NVMe.

**Architecture:** l'immagine (repo pubblico) porta solo meccanismi generici: script, unit systemd, symlink dei percorsi ADM. Tutto ciò che descrive *questa* casa (elenco stack, cosa salvare, compose dei container senza compose) sta nel repo privato `nas-stacks`, copiato sul NAS in `/etc/nas-os/`. I segreti restano solo sul NAS.

**Tech Stack:** bootc, systemd, Docker Compose, rsync su SSH, Samba, Tailscale, bootc-image-builder (anaconda-iso), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-27-nas-os-design.md` (§6.6, §6.7, §7)

## Fatti misurati sul NAS (27/10/2026)

- 51 container attivi. Quasi tutti hanno un compose in `/volume1/Docker/<nome>` o `/share/Docker/<nome>`. Senza compose (avviati da ADM/App Central): Home-Assistant, Nextcloud, Syncthing, postgres-17, vaultwarden_mysql, pihole, PortainerCE, Dozzle vecchio.
- `/share/<cartella>` e `/volume1/<cartella>` sono la stessa cosa (md1 montato in entrambi).
- La radice Docker è su md1: `/volume1/.@plugins/AppCentral/docker-ce/docker_lib`. Volumi con nome e dati veri: `abs-import_abs-import-dati`, `claudebridge_claude_credentials`, `opengym_opengym-dati`, `opengym_opengym-coach`.
- Tailscale: stato in `/volume1/Docker/Tailscale/tailscaled.state` (+ `tka-profiles`, tailnet lock attivo).
- Pi-hole usa la porta 53 in rete host → su Fedora va spento lo stub di systemd-resolved.
- WD: `rsync` presente (protocollo 31), chiave del NAS già autorizzata (utente `sshd`).
- TelegramNotifier: `POST /send` con autenticazione, porta 3086.

## Global Constraints

- Repo `nas-os` pubblico: niente nomi di servizi, percorsi della casa, IP, email; tutto questo va in `nas-stacks` (privato). `tests/secrets-scan.sh` deve passare.
- `nas-stacks`: stesso scanner + gitleaks in CI prima del primo push; `.env` e chiavi mai committati.
- Nessuno script tocca md1 in scrittura finché l'utente non l'ha rimontato `rw` (vedi spec §7.4); gli script che leggono da md1 devono funzionare anche con md1 `ro`.
- Installatore: deve toccare SOLO l'NVMe. eMMC (ADM) e HDD mai.
- Le eliminazioni sul WD non sono mai definitive: ciò che sparisce dal NAS va in una cartella cestino datata sul WD.
- Zero riscritture dei compose esistenti: si avviano dove sono.

## Review Focus

1. md1 ancora `ro` al primo avvio: nas-stacks non deve tentare di avviare nulla (né fallire in loop) finché i dati sono in sola lettura.
2. Uno stack rotto non deve impedire l'avvio degli altri.
3. Backup con WD spento o irraggiungibile: errore e avviso Telegram, mai cancellazioni sul NAS.
4. Installatore con più dischi: con HDD ed eMMC presenti deve vedere solo l'NVMe.
5. Tailscale con stato copiato mentre ADM è ancora acceso sullo stesso nodo: doppione dell'identità → lo script si rifiuta se trova il nodo raggiungibile.

---

### Task 1: Percorsi ADM e rete di base

**Files:** Create `build_files/steps/50-servizi.sh`, `system_files/usr/lib/systemd/resolved.conf.d/10-nas.conf`; Modify `tests/image-checks.sh`

- [ ] **Test (image-checks, sezione "Servizi"):** `/volume1` e `/share` sono symlink a `var/mnt/dati`; `DNSStubListener=no`; `docker.service` abilitato; `tailscaled.service` abilitato; interfaccia `tailscale0` nella zona `trusted`.
- [ ] **Implementazione:** symlink creati nello step (`ln -s var/mnt/dati /volume1` ecc.), drop-in resolved, `systemctl enable docker tailscaled`, `firewall-offline-cmd --zone=trusted --add-interface=tailscale0`.
- [ ] Build CI verde, commit `feat: percorsi ADM, docker e tailscale`.

### Task 2: Avvio degli stack (`nas-stacks.service`)

**Files:** Create `system_files/usr/libexec/nas-os/avvia-stack`, `system_files/usr/lib/systemd/system/nas-stacks.service`, `system_files/etc/nas-os/stacks.conf` (vuoto con commento), `tests/avvia-stack.sh`

**Interfaces:** `avvia-stack [file conf]` — una cartella per riga (commenti `#`), per ognuna `docker compose up -d`; riepilogo `OK n / FALLITI m`; exit 1 se almeno uno fallisce. Se `/var/mnt/dati` non è montato `rw`: messaggio e exit 0 senza avviare nulla. Variabili per i test: `DOCKER`, `DATI`.

- [ ] **Test** con `docker` finto: 3 cartelle, la seconda fallisce → la terza parte comunque, exit 1, riepilogo corretto; dati `ro` → nessuna chiamata a docker, exit 0; righe vuote e commenti ignorati; cartella inesistente → contata come fallita.
- [ ] Implementazione; unit `Type=oneshot`, `After=docker.service var-mnt-dati.mount network-online.target`, abilitata.
- [ ] Commit `feat: avvio stack da elenco, uno rotto non ferma gli altri`.

### Task 3: Volumi Docker e Tailscale da ADM

**Files:** Create `system_files/usr/libexec/nas-os/migra-volumi`, `system_files/usr/libexec/nas-os/adotta-tailscale`, `tests/migra-volumi.sh`

**Interfaces:**
- `migra-volumi <vecchia radice docker> <volume>...` — per ogni volume: crea il volume se manca, copia `_data` con `cp -a`; rifiuta se il volume nuovo esiste già e non è vuoto. Variabili test: `DOCKER`.
- `adotta-tailscale <cartella stato ADM>` — ferma tailscaled, copia stato in `/var/lib/tailscale`, riavvia; rifiuta se `tailscaled.state` manca.

- [ ] **Test** `migra-volumi` con docker finto e cartelle finte: copia contenuto e permessi; volume già pieno → rifiuta senza toccarlo; volume sorgente assente → errore chiaro.
- [ ] Implementazione + chmod nello step 50; commit `feat: migrazione volumi e identità tailscale da ADM`.

### Task 4: Condivisioni Samba

**Files:** Create `system_files/etc/samba/smb.conf`; Modify `50-servizi.sh`, `tests/image-checks.sh`

- [ ] **Test:** `testparm -s` valido; `hosts allow` con le reti fidate di `vars.sh`; `smb.service` abilitato; servizio firewall `samba` solo tramite rich rule sulle reti fidate (come Cockpit).
- [ ] **Implementazione:** `[global]` con `include = registry` (così le condivisioni le gestisce `cockpit-file-sharing`), `hosts allow`, niente ospiti. Le condivisioni vere (Docker, Download, Music, Photos, Public, Video, Web, home) le scrive `nas-stacks` con `net conf import` dopo il primo avvio.
- [ ] Commit `feat: samba gestito da cockpit, solo reti fidate`.

### Task 5: Backup notturno sul WD

**Files:** Create `system_files/usr/libexec/nas-os/backup`, `system_files/usr/libexec/nas-os/avviso`, `system_files/usr/lib/systemd/system/nas-backup.{service,timer}`, `system_files/usr/lib/systemd/system/nas-avviso@.service`, `system_files/etc/nas-os/backup.conf` (esempio commentato), `tests/backup.sh`

**Interfaces:**
- `backup [conf]` — `backup.conf` (shell): `DEST=utente@host:cartella`, `CHIAVE=/var/lib/nas-os/secrets/wd_key`, array `SORGENTI=(cartella...)`, array `DUMP=("nome|comando")`. Prima esegue i `DUMP` in `/var/mnt/dati/.nas-backup/dump/<nome>.sql.gz`, poi `rsync -aH --delete --backup --backup-dir=.cestino/<AAAA-MM-GG>` per ogni sorgente. Exit ≠ 0 al primo errore, senza proseguire con altri `--delete`.
- `avviso <unità>` — `POST` a TelegramNotifier con token da `/var/lib/nas-os/secrets/telegram.env`.

- [ ] **Test** con `rsync`/`ssh` finti: argomenti `--backup-dir` con data, `--delete` presente; dump fallito → nessun rsync, exit ≠ 0; conf mancante → exit ≠ 0 con messaggio.
- [ ] Timer alle 03:30 con `Persistent=true`; `OnFailure=nas-avviso@%n.service`. Il timer è abilitato, ma senza `backup.conf` reale il servizio esce con errore chiaro (e avviso).
- [ ] Commit `feat: backup notturno sul WD con cestino e avviso telegram`.

### Task 6: ISO d'installazione

**Files:** Create `disk_config/iso.toml`, `.github/workflows/build-disk.yml` (da air-os)

- [ ] `iso.toml`: kickstart con `ignoredisk --only-use=nvme0n1`, `clearpart --all --initlabel --drives=nvme0n1`, `autopart --nohome`, utente `daniele` con chiave SSH pubblica, gruppo `wheel`, nessuna password; `bootc switch` firmato verso `ghcr.io/drdamnation/nas-os:stable` già incluso dall'immagine.
- [ ] **Test** (step CI prima della build): il kickstart contiene `--only-use=nvme0n1` e nessun `sd`/`mmcblk`; la chiave è pubblica (`ssh-ed25519 …`), mai `PRIVATE`.
- [ ] CI produce `install.iso` come artefatto; commit `feat: iso che installa solo sull'NVMe`.

### Task 7: Repo privato `nas-stacks`

**Files (repo `DrDamnation/nas-stacks`):** `stacks/<nome>/compose.yaml` copiati dal NAS, `stacks/<nome>/` con i Dockerfile dei container fatti in casa, `adm/<nome>/compose.yaml` scritti per gli 8 container senza compose, `etc/stacks.conf`, `etc/backup.conf`, `etc/smb-condivisioni.conf`, `installa.sh` (copia `etc/*` in `/etc/nas-os/`), scanner + gitleaks + hook.

- [ ] Copia dei compose senza `.env`; scansione locale (`secrets-scan.sh` + gitleaks): **zero** riscontri prima del primo commit. I segreti scritti dentro i compose si spostano in `.env` sul NAS.
- [ ] Compose per gli 8 container ricavati da `docker inspect` (immagine, porte, mount, rete, restart); env solo per nome, valori in `.env`.
- [ ] `stacks.conf` nell'ordine: database → servizi → proxy/tunnel. Esclusi: container `*-old-*`/`vecchio`, `tailscale-runner`, `tailscale-funnels`, `watchtower`, `nginx-proxy-manager` (fermi o sostituiti da nas-os).
- [ ] `backup.conf`: originali Immich, Vaultwarden, Paperless (export), dump di `postgres-17`, `ImmichPostgres`, `paperless-db`, `vaultwarden_mysql`, `romm-db`.
- [ ] CI verde, commit.

### Task 8: Chiavetta

- [ ] Scaricare `install.iso` dall'artefatto CI, verificare sha256.
- [ ] Verificare che `G:` sia ancora il disco Kingston DataTraveler G3 da 16 GB (numero disco, modello, dimensione); scrivere l'ISO sul disco fisico; rileggere e confrontare lo sha256 dei primi N byte.
- [ ] Aggiornare la memoria del progetto.
