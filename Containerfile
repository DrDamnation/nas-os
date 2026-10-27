# Contesto di build: script, file di sistema e test (non finiscono nell'immagine se non copiati)
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files
COPY tests /tests

# nas-os: Fedora CoreOS 44 con Docker, Cockpit, Samba, NFS e Tailscale (base Universal Blue uCore)
FROM ghcr.io/ublue-os/ucore:stable

ARG GIT_SHA=unknown

# kernel-devel per compilare il driver Asustor: stessi RPM del kernel di uCore stable
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=ghcr.io/ublue-os/akmods:coreos-stable-44,source=/kernel-rpms,target=/tmp/kernel-rpms \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    GIT_SHA="${GIT_SHA}" /ctx/build.sh

RUN bootc container lint
