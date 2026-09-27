#!/bin/bash
# Derivative image kernel swap: replaces the base image's kernel tarball-style
# with the fork kernel (/packages/kernel), regenerating the initramfs in place.
# Mirrors build_files/20-install-kernel.sh + 55-generate-initramfs.sh but
# touches NO third-party repo (terra44 incident-safe): no dnf install, local
# rpmdb only, with a fedora-repos-only dracut fallback if dracut is missing.
set -euxo pipefail

shopt -s nullglob
tarballs=(/packages/kernel/armada-kernel-*.tar.zst)
if [ "${#tarballs[@]}" -ne 1 ]; then
    echo "ERROR: expected exactly one kernel tarball" >&2
    exit 1
fi
TARBALL="${tarballs[0]}"
KVER="${TARBALL##*/armada-kernel-}"
KVER="${KVER%.tar.zst}"

( cd /packages/kernel && sha256sum -c "armada-kernel-${KVER}.tar.zst.sha256" )

# bootc expects exactly one kernel under /usr/lib/modules. The base image's
# kernel was installed from a tarball (not rpm), so clear rpm entries if any
# then wipe the tree.
rpm -qa 'kernel*' 2>/dev/null | xargs -r rpm -e --nodeps 2>/dev/null || true
rm -rf /usr/lib/modules/*

tar --extract --zstd -f "${TARBALL}" -C /usr/
depmod -a "${KVER}" -b /

# dracut introspection wants these paths (see 55-generate-initramfs.sh).
mkdir -p /var/roothome

if ! command -v dracut >/dev/null; then
    # terra44 est en incident : n'utiliser QUE les dépôts Fedora.
    dnf5 -y --disablerepo='*terra*' install dracut
fi

dracut \
    --force \
    --no-hostonly \
    --reproducible \
    --kver "${KVER}" \
    --add ostree \
    --add armada-splash \
    --add armada-ostree-fallback \
    "/usr/lib/modules/${KVER}/initramfs.img" "${KVER}"

size=$(stat -c %s "/usr/lib/modules/${KVER}/initramfs.img")
[ "${size}" -gt 5000000 ] || { echo "initramfs trop petit (${size})"; exit 1; }

echo "sleepexp kernel ${KVER} installé (initramfs $((${size}/1024/1024)) Mo)"
