#!/usr/bin/env bash
# Build AtlasA1 Linux/PVR from upstream Linux and the configured T736 Tina SDK.
set -euo pipefail
case "${4-}:$#" in
    :3) build=30; release=6.18.63-t736-media-v30 ;;
    --wireless-v31:4) build=31; release=6.18.63-t736-hw-v31 ;;
    --hardware-v33:4) build=33; release=6.18.63-t736-hw-v33 ;;
    --pcie-v34:4) build=34; release=6.18.63-t736-hw-v34 ;;
    *) echo "usage: $0 LINUX_ARCHIVE_OR_GIT_REPO TINA_SDK NEW_OUTPUT [--wireless-v31|--hardware-v33|--pcie-v34]" >&2; exit 2 ;;
esac
upstream=$(realpath -e "$1")
tina=$(realpath -e "$2")
work=$(realpath -m "$3")
tools=$(cd "$(dirname "$0")" && pwd)
linux="$work/linux"
kernel="$work/kout"
pvr="$work/pvr-src"
version=6.18.63-$build
jobs=${JOBS:-8}
input=--archive
if [[ -d $upstream ]]; then input=--upstream; fi
mkdir -- "$work"
python3 "$tools/prepare_atlas_release_sources.py" linux "$input" "$upstream" --tina "$tina" --output "$linux"
python3 "$tools/prepare_atlas_release_sources.py" pvr --tina "$tina" --output "$pvr"
mkdir "$kernel"
cp "$linux/.config.atlasa1" "$kernel/.config"
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- KBUILD_BUILD_VERSION="$build"
export SOURCE_DATE_EPOCH=1794960000 KBUILD_BUILD_TIMESTAMP='2026-11-18 00:00:00 UTC'
export KBUILD_BUILD_USER=ubuntu KBUILD_BUILD_HOST=ubuntu2404 TZ=UTC
kmake=(make -C "$linux" O="$kernel" -j"$jobs")
dtb_name=t736-gpu-candidate.dtb
if [[ $build != 30 ]]; then
    root=$(dirname "$tools")
    fragment="$root/boards/wireless-v31/kernel.config"
    patches=(atlasa1-wireless-v31.patch)
    if [[ $build == 33 || $build == 34 ]]; then
        patches+=(atlasa1-pcie-v32.patch atlasa1-wireless-dldo5-v33.patch
                  atlasa1-wireless-reset-v33.patch atlasa1-pcie-combo1-v33.patch)
        if [[ $build == 34 ]]; then
            patches+=(atlasa1-pcie-pipe-map-v34.patch)
            (cd "$root" && sha256sum --strict -c boards/pcie-v32/hw-v34-inputs.sha256)
        fi
        dtb_name=t736-pcie-v32.dtb
        awk '!/^CONFIG_LOCALVERSION=/' "$fragment" "$root/boards/pcie-v32/pcie.config" > "$work/hardware.config"
        printf 'CONFIG_LOCALVERSION="-t736-hw-v%s"\n' "$build" >> "$work/hardware.config"
        fragment="$work/hardware.config"
    fi
    for entry in "${patches[@]}"; do
        patch --batch --forward --fuzz=0 -d "$linux" -p1 -i "$root/patches/linux/$entry"
    done
    "$linux/scripts/kconfig/merge_config.sh" -m -O "$kernel" "$kernel/.config" "$fragment"
fi
"${kmake[@]}" olddefconfig
if [[ $build == 30 ]]; then
    cmp "$linux/.config.atlasa1" "$kernel/.config"
else
    while IFS= read -r entry; do
        grep -Fxq "$entry" "$kernel/.config" || { echo "Unresolved Kconfig setting: $entry" >&2; exit 1; }
    done < "$fragment"
fi
"${kmake[@]}" Image "allwinner/$dtb_name" modules
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
dtb=kout/arch/arm64/boot/dts/allwinner/$dtb_name
test "$(fdtget -t s "$dtb" / compatible | cut -d' ' -f1)" = allwinner,t736
sha256sum "$deb" kout/arch/arm64/boot/Image "$dtb" pvr-out/target_aarch64/kbuild/pvrsrvkm.ko > SHA256SUMS
