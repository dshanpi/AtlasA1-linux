#!/usr/bin/env bash
# Build v30 Linux/PVR from upstream Linux and the configured T736 Tina SDK.
set -euo pipefail
[[ $# == 3 ]] || { echo "usage: $0 LINUX_ARCHIVE_OR_GIT_REPO TINA_SDK NEW_OUTPUT" >&2; exit 2; }
upstream=$(realpath -e "$1")
tina=$(realpath -e "$2")
work=$(realpath -m "$3")
tools=$(cd "$(dirname "$0")" && pwd)
linux="$work/linux"
kernel="$work/kout"
pvr="$work/pvr-src"
release=6.18.63-t736-media-v30
version=6.18.63-30
jobs=${JOBS:-8}
input=--archive
if [[ -d $upstream ]]; then input=--upstream; fi
mkdir -- "$work"
python3 "$tools/prepare_atlas_release_sources.py" linux "$input" "$upstream" --tina "$tina" --output "$linux"
python3 "$tools/prepare_atlas_release_sources.py" pvr --tina "$tina" --output "$pvr"
mkdir "$kernel"
cp "$linux/.config.atlasa1" "$kernel/.config"
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- KBUILD_BUILD_VERSION=30
export SOURCE_DATE_EPOCH=1794960000 KBUILD_BUILD_TIMESTAMP='2026-11-18 00:00:00 UTC'
export KBUILD_BUILD_USER=ubuntu KBUILD_BUILD_HOST=ubuntu2404 TZ=UTC
kmake=(make -C "$linux" O="$kernel" -j"$jobs")
"${kmake[@]}" olddefconfig
cmp "$linux/.config.atlasa1" "$kernel/.config"
"${kmake[@]}" Image allwinner/t736-gpu-candidate.dtb modules
DEB_BUILD_PROFILES=pkg.linux-upstream.nokernelheaders "${kmake[@]}" KDEB_PKGVERSION="$version" bindeb-pkg
test "$(cat "$kernel/include/config/kernel.release")" = "$release"
out="$work/pvr-out"
kbuild="$out/target_aarch64/kbuild"
# The DDK's out-of-tree Kbuild references the source C files under its object tree.
cd "$pvr"
while IFS= read -r -d '' path; do
    mkdir -p -- "$kbuild/$(dirname -- "$path")"
    ln -s -- "$pvr/$path" "$kbuild/$path"
done < <(find . -path ./build -prune -o -name '*.c' -type f -print0)
make -C build/linux/sunxi_linux -j"$jobs" KERNELDIR="$kernel" OUT="$out" \
    KERNEL_CC=aarch64-linux-gnu-gcc KERNEL_LD=aarch64-linux-gnu-ld \
    KERNEL_NM=aarch64-linux-gnu-gcc-nm KERNEL_OBJCOPY=aarch64-linux-gnu-objcopy \
    GPU_BUILD_TYPE=release BUILD=release SUPPORT_LINUX_DVFS=0 SUPPORT_PDVFS=0 \
    SUPPORT_DMA_FENCE=1 SUPPORT_BUFFER_SYNC=1
[[ $(modinfo -F vermagic "$kbuild/pvrsrvkm.ko") == "$release "* ]]
cd "$work"
deb="linux-image-${release}_${version}_arm64.deb"
test "$(dpkg-deb -f "$deb" Package)" = "linux-image-$release"
dtb=kout/arch/arm64/boot/dts/allwinner/t736-gpu-candidate.dtb
test "$(fdtget -t s "$dtb" / compatible | cut -d' ' -f1)" = allwinner,t736
sha256sum "$deb" kout/arch/arm64/boot/Image "$dtb" pvr-out/target_aarch64/kbuild/pvrsrvkm.ko > SHA256SUMS
