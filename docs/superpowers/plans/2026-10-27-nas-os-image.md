# nas-os, prima immagine — piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** immagine bootc `ghcr.io/drdamnation/nas-os:stable` costruita, testata e firmata in CI, con driver Asustor, Cockpit 45Drives e configurazione dischi sicura. Il NAS non si tocca.

**Architecture:** copia della struttura di `C:\Users\danie\projects\air-os` (Containerfile → `build_files/build.sh` → `steps/NN-*.sh`, `system_files/` copiati su `/`, `tests/image-checks.sh` eseguito dentro l'immagine in CI). Base `ghcr.io/ublue-os/ucore:stable`; `kernel-devel` dagli RPM di `ghcr.io/ublue-os/akmods:coreos-stable-44` (`/kernel-rpms`).

**Tech Stack:** bootc, podman, just, GitHub Actions, cosign, bash, Fedora CoreOS 44.

**Spec:** `docs/superpowers/specs/2026-10-27-nas-os-design.md`

**Fuori da questo piano (piani successivi):** step 50-servizi (nas-stacks, Tailscale), 60-backup (WD), ISO d'installazione (`disk_config/`), installazione sul NAS.

## Global Constraints

- Repo pubblico: nessun segreto né dato personale; `tests/secrets-scan.sh` deve passare a ogni commit (hook) e in CI.
- Commit con identità `DrDamnation <37379581+DrDamnation@users.noreply.github.com>`.
- Ogni sorgente scaricato ha versione fissata e sha256 in `build_files/steps/vars.sh`.
- `md0` e `md126` (sistema e swap ADM) non devono mai essere assemblati; `md1` si monta solo `ro` finché non è verificato.
- Aggiornamenti solo manuali: timer `bootc-fetch-apply-updates` e `rpm-ostreed-automatic` spenti, Zincati spento.
- Cockpit raggiungibile solo da reti private e Tailscale (192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 100.64.0.0/10).
- La build fallisce se un modulo asustor non esiste per il kernel dell'immagine.

## Review Focus

1. Kernel di uCore ≠ kernel-devel di akmods → il modulo compila per la versione sbagliata: `modinfo -k $KVER` in build e test.
2. initramfs che assembla da solo gli array ADM (dracut mdraid): karg `rd.md=0` + `AUTO -all`, verificati in image-checks.
3. Volume dati assente o array non ancora adottato: il mount di `md1` non deve bloccare l'avvio (`nofail`, timeout breve).
4. Hardware non presente (CI, o driver che non carica sul NAS): `fancontrol` non deve rompere l'avvio; la ventola resta al valore BIOS.
5. Cockpit aperto su internet per regola firewall sbagliata: test che il servizio non sia aperto a tutti nella zona public.

---

### Task 1: Scheletro build e firma

**Files:**
- Create: `Containerfile`, `Justfile`, `image-template.env`, `cosign.pub`, `build_files/build.sh`, `build_files/steps/vars.sh`, `build_files/steps/10-signing.sh`, `build_files/steps/90-finalize.sh`, `system_files/etc/containers/registries.d/nas-os.yaml`, `system_files/etc/pki/containers/nas-os.pub`, `tests/lib.sh`, `tests/image-checks.sh`, `.github/workflows/build.yml`, `README.md`

**Interfaces:**
- Produces: `vars.sh` (sorgente da ogni step), `/usr/share/nas-os/tests/{lib.sh,image-checks.sh}`, `/usr/share/nas-os/build-info`, `check`/`section`/`finish` di `lib.sh`.

- [ ] **Step 1:** copiare da air-os `Justfile` (invariato), `tests/lib.sh` (invariato), `build.yml` (path test `/usr/share/nas-os/tests/image-checks.sh`, niente bats). `image-template.env`: `IMAGE_NAME=nas-os`, `IMAGE_DESC="nas-os: Asustor AS6702T"`.
- [ ] **Step 2:** `Containerfile`: `FROM ghcr.io/ublue-os/ucore:stable`, mount `akmods:coreos-stable-44` `/kernel-rpms` → `/tmp/kernel-rpms`, poi `bootc container lint`.
- [ ] **Step 3:** chiave cosign nuova (`cosign generate-key-pair`), privata nel segreto `SIGNING_SECRET` di GitHub e poi cancellata dal disco; `10-signing.sh` come air-os con `ghcr.io/drdamnation/nas-os`.
- [ ] **Step 4:** `90-finalize.sh`: timer spenti, `zincati.service` mascherato se presente, build-info, `dnf5 clean all`.
- [ ] **Step 5:** image-checks sezioni "Base" (Fedora 44, timer spenti, zincati non attivo, build-info) e "Firma" (come air-os).
- [ ] **Step 6:** build locale `podman build` (o in CI se il PC non ha podman) e `image-checks.sh` → tutto PASS.
- [ ] **Step 7:** commit `feat: scheletro immagine nas-os su uCore stable`.

### Task 2: Driver Asustor (20-kernel-modules)

**Files:** Create `build_files/steps/20-kernel-modules.sh`; Modify `vars.sh`, `tests/image-checks.sh`

**Interfaces:** Produces moduli `asustor`, `asustor_it87`, `asustor_gpio_it87` in `/usr/lib/modules/$KVER/extra/asustor/`.

- [ ] **Step 1: test** in image-checks, sezione "Driver Asustor": per ogni modulo `check "<mod> per $KVER" modinfo -k "$KVER" <mod>`; `check "niente kernel-devel" ! rpm -q kernel-devel`; `check "niente gcc" ! rpm -q gcc`.
- [ ] **Step 2:** build → FAIL sui tre moduli.
- [ ] **Step 3:** `vars.sh`: `ASUSTOR_DRIVER_COMMIT=394a6486c238cd4f25069205b39b039addd5bd36`, `ASUSTOR_DRIVER_SHA256=23c3ce1b41547dacc6483b560bf6ea4d43a8fd8d3769357cf6b648dd38ed1761` (archivio `https://github.com/DrDamnation/asustor-platform-driver/archive/<commit>.tar.gz`). Step: `dnf5 install gcc make /tmp/kernel-rpms/kernel-devel-${KVER}.rpm`, `make -C /usr/src/kernels/$KVER M=<src> modules`, install, `depmod -a`, rimozione toolchain (come facetimehd in air-os). Se `kernel-devel-${KVER}.rpm` non esiste la build deve fallire con messaggio chiaro.
- [ ] **Step 4:** build → PASS.
- [ ] **Step 5:** commit `feat: driver asustor compilato per il kernel dell'immagine`.

### Task 3: Hardware AS6702T (25-asustor-hardware)

**Files:** Create `build_files/steps/25-asustor-hardware.sh`, `system_files/usr/lib/bootc/kargs.d/10-nas.toml`, `system_files/usr/lib/modules-load.d/asustor.conf`, `system_files/usr/libexec/nas-os/fancontrol-config`, `system_files/usr/lib/systemd/system/fancontrol.service.d/10-nas.conf`

**Interfaces:** Produces `/usr/libexec/nas-os/fancontrol-config <out>` → scrive config fancontrol cercando gli hwmon per nome (`it86*` con `pwm1` per la ventola, `coretemp` per la temperatura); exit 1 se mancano.

- [ ] **Step 1: test**: `kargs.d` contiene `acpi_enforce_resources=lax`; `modules-load.d/asustor.conf` elenca i tre moduli; `rpm -q lm_sensors`; fancontrol abilitato; `fancontrol-config /tmp/x` in CI (senza hardware) esce ≠0 e non scrive `/tmp/x`.
- [ ] **Step 2:** build → FAIL.
- [ ] **Step 3:** implementare. Curva: `MINTEMP=45`, `MAXTEMP=75`, `MINSTART=150`, `MINSTOP=80`, `MINPWM=80`. Drop-in fancontrol: `ExecStartPre=/usr/libexec/nas-os/fancontrol-config /run/fancontrol`, `ExecStart=` rimpiazzato con `/usr/sbin/fancontrol /run/fancontrol`; se il pre fallisce, il servizio fallisce e la ventola resta al BIOS (accettato dalla spec).
- [ ] **Step 4:** build → PASS. Commit `feat: kargs, moduli e ventola AS6702T`.

### Task 4: Dischi sicuri (30-storage)

**Files:** Create `build_files/steps/30-storage.sh`, `system_files/etc/mdadm.conf`, `system_files/usr/lib/systemd/system/var-mnt-dati.mount`, `system_files/usr/libexec/nas-os/adotta-md1`; Modify `10-nas.toml`

**Interfaces:** Produces `adotta-md1` (da lanciare a mano sul NAS): legge `mdadm --examine --scan`, sceglie l'array delle partizioni `sd?4`, aggiunge `ARRAY /dev/md/dati metadata=1.2 UUID=<uuid>` a `/etc/mdadm.conf`, rifiuta se trova più candidati o nessuno.

- [ ] **Step 1: test**: karg `rd.md=0`; `/etc/mdadm.conf` contiene `AUTO -all` e nessuna riga `ARRAY`; mount `What=/dev/md/dati`, `Options` contiene `ro`, `nofail`, `x-systemd.device-timeout=10s`; mount abilitato; `smartd` e `rpm -q smartmontools mdadm` ok; `raid-check.timer` abilitato.
- [ ] **Step 2: test di `adotta-md1`** con `mdadm` finto nel PATH (in `tests/adotta-md1.sh`, eseguito in CI fuori dall'immagine): output di tre array (`md0`, `md126`, `md1` con devices `/dev/sda4,/dev/sdb4`) → scrive solo l'UUID di md1; due candidati → exit 1 senza scrivere; nessuno → exit 1.
- [ ] **Step 3:** build e test → FAIL.
- [ ] **Step 4:** implementare; `adotta-md1` accetta `MDADM_CONF` per il test.
- [ ] **Step 5:** PASS. Commit `feat: md1 in sola lettura, array ADM mai assemblati`.

### Task 5: Pannello Cockpit (40-cockpit)

**Files:** Create `build_files/steps/40-cockpit.sh`; Modify `vars.sh`, `tests/image-checks.sh`

- [ ] **Step 1: test**: `rpm -q cockpit-file-sharing cockpit-identities`; `test -f /usr/share/cockpit/navigator/manifest.json`; cockpit NON tra i servizi della zona public; 4 rich rule cockpit (reti della Global Constraints).
- [ ] **Step 2:** build → FAIL.
- [ ] **Step 3:** `vars.sh`:
  - `FILE_SHARING_VERSION=4.6.3`, sha256 `e095634d46d0487a8c3445e4fb11360bc6ddf4ac054e9a8b370cda19c552b2d1` (el9 noarch rpm)
  - `IDENTITIES_VERSION=0.1.14-1`, sha256 `75e7d5f80460233a03f3722b80b04ec1a294b9fbd4b4e9b2e3e991e2b5615cf1`
  - `NAVIGATOR_VERSION=0.5.14-1`, sha256 `d53825143edc7bfc57c7d0d1a0afca7404f98413b3c4ee499698e0010c5cd434` (tarball sorgente: la 0.5.14 non ha RPM; si copia `navigator/` in `/usr/share/cockpit/navigator`)
  - firewall con `firewall-offline-cmd` come RustDesk in air-os.
- [ ] **Step 4:** PASS. Commit `feat: cockpit 45drives solo da LAN e Tailscale`.

### Task 6: CI verde e immagine su GHCR

- [ ] **Step 1:** push su `main`; workflow "controllo segreti" e "Build container image" verdi.
- [ ] **Step 2:** `skopeo inspect docker://ghcr.io/drdamnation/nas-os:stable` risponde; `cosign verify --key cosign.pub` ok; pacchetto GHCR pubblico.
- [ ] **Step 3:** aggiornare memoria `project_nas_os.md` con lo stato.
