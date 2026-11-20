#!/usr/bin/env bash
# Experimental GNOME display candidates; never changes the default image recipe.
set -euo pipefail
case "${4-}:$#" in
    :3) build=36; rate=400000000 ;;
    --gpu600:4) build=37; rate=600000000 ;;
    --rcq-preempt:4) build=38; rate=400000000 ;;
    --rcq-poll:4) build=39; rate=400000000 ;;
    --cedar-import:4) build=40; rate=400000000 ;;
    --prime-scanout:4) build=41; rate=400000000 ;;
    --display-trace:4) build=42; rate=400000000 ;;
    --pcie-nvme:4) build=45; rate=400000000 ;;
    --boot-log:4) build=46; rate=400000000 ;;
    --boot-fast:4) build=47; rate=400000000 ;;
    *) echo "Usage: $0 LINUX_ARCHIVE_OR_GIT_REPO TINA_SDK NEW_OUTPUT [--gpu600|--rcq-preempt|--rcq-poll|--cedar-import|--prime-scanout|--display-trace|--pcie-nvme|--boot-log|--boot-fast]" >&2; exit 2 ;;
esac
upstream=$(realpath -e "$1")
tina=$(realpath -e "$2")
work=$(realpath -m "$3")
tools=$(cd "$(dirname "$0")" && pwd)
patches="$tools/../patches/linux/gnome-media-20261119"
input=--archive
if [[ -d $upstream ]]; then input=--upstream; fi
mkdir -- "$work"
python3 "$tools/prepare_atlas_release_sources.py" linux "$input" "$upstream" --tina "$tina" --output "$work/linux"
python3 "$tools/prepare_atlas_release_sources.py" pvr --tina "$tina" --output "$work/pvr-src"
patch --batch --forward --fuzz=0 -d "$work/linux" -p1 -i "$patches/v36-vblank.patch"
if [[ $build == 37 ]]; then
    patch --batch --forward --fuzz=0 -d "$work/linux" -p1 -i "$patches/v37-gpu600-linux.patch"
    patch --batch --forward --fuzz=0 -d "$work/pvr-src" -p1 -i "$patches/v37-gpu600-pvr.patch"
fi
if (( build >= 38 )); then
    patch --batch --forward --fuzz=0 -d "$work/linux" -p1 -i "$patches/v38-rcq-poll.patch"
fi
if (( build >= 40 )); then
    patch --batch --forward --fuzz=0 -d "$work/linux" -p1 -i "$patches/v40-cedar-import.patch"
fi
if (( build >= 41 )); then
    patch --batch --forward --fuzz=0 -d "$work/linux" -p1 -i "$patches/v41-prime-scanout.patch"
fi
if (( build >= 42 )); then
    patch --batch --forward --fuzz=0 -d "$work/linux" -p1 -i "$patches/v42-trace-api.patch"
    patch --batch --forward --fuzz=0 -d "$work/pvr-src" -p1 -i "$patches/v42-pvr-trace-api.patch"
fi
if (( build >= 46 )); then
    patch --batch --forward --fuzz=0 -d "$work/linux" -p1 -i "$patches/v46-mmc-tuning-log.patch"
fi
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- KBUILD_BUILD_VERSION="$build" LOCALVERSION=
export SOURCE_DATE_EPOCH=1795046400 KBUILD_BUILD_TIMESTAMP='2026-11-19 00:00:00 UTC'
export KBUILD_BUILD_USER=ubuntu KBUILD_BUILD_HOST=ubuntu2404 TZ=UTC
v="6.18.63-t736-gnome-v$build"
kernel="$work/kout"
mkdir "$kernel"
cp "$work/linux/.config.atlasa1" "$kernel/.config"
dtb_name=t736-gpu-candidate.dtb
if (( build >= 43 )); then
    root=$(dirname "$tools")
    (cd "$root" && sha256sum --strict -c boards/pcie-v32/hw-v34-inputs.sha256)
    for entry in atlasa1-wireless-v31.patch atlasa1-pcie-v32.patch \
                 atlasa1-wireless-dldo5-v33.patch atlasa1-wireless-reset-v33.patch \
                 atlasa1-pcie-combo1-v33.patch atlasa1-pcie-pipe-map-v34.patch \
                 atlasa1-pcie-dma-v43.patch atlasa1-pcie-aspm-v45.patch; do
        patch --batch --forward --fuzz=0 -d "$work/linux" -p1 -i "$root/patches/linux/$entry"
    done
    awk '!/^CONFIG_LOCALVERSION=/' "$root/boards/wireless-v31/kernel.config" \
        "$root/boards/pcie-v32/pcie.config" > "$work/hardware.config"
    # Keep the root port managed after enumeration, including bridge PM.
    printf 'CONFIG_PCIEPORTBUS=y\n' >> "$work/hardware.config"
    "$work/linux/scripts/kconfig/merge_config.sh" -m -O "$kernel" "$kernel/.config" "$work/hardware.config"
    dtb_name=t736-pcie-v32.dtb
fi
"$work/linux/scripts/config" --file "$kernel/.config" --set-str LOCALVERSION "-t736-gnome-v$build"
if [[ $build == 38 ]]; then
    echo 'WARNING: v38 caused Xorg kernel Oops on hardware; diagnostic rebuild only.' >&2
    "$work/linux/scripts/config" --file "$kernel/.config" --enable PREEMPT_DYNAMIC
fi
if (( build >= 39 )); then
    "$work/linux/scripts/config" --file "$kernel/.config" --disable PREEMPT_DYNAMIC --disable PREEMPT --enable PREEMPT_NONE --enable PREEMPT_NONE_BUILD
fi
if (( build >= 42 )); then
    "$work/linux/scripts/config" --file "$kernel/.config" --enable FTRACE --enable FUNCTION_TRACER --enable FUNCTION_GRAPH_TRACER
fi
if (( build >= 47 )); then
    "$work/linux/scripts/config" --file "$kernel/.config" --set-val CONSOLE_LOGLEVEL_DEFAULT 5
fi
km=(make -C "$work/linux" O="$kernel" -j"${JOBS:-7}")
"${km[@]}" olddefconfig
if (( build >= 43 )); then
    while IFS= read -r entry; do
        grep -Fxq "$entry" "$kernel/.config" || { echo "Unresolved Kconfig setting: $entry" >&2; exit 1; }
    done < "$work/hardware.config"
fi
if [[ $build == 38 ]]; then
    grep -qx CONFIG_PREEMPT_DYNAMIC=y "$kernel/.config"
    grep -qx CONFIG_PREEMPT_NONE=y "$kernel/.config"
fi
"${km[@]}" Image modules "allwinner/$dtb_name"
test "$(cat "$kernel/include/config/kernel.release")" = "$v"
test "$(fdtget -t u "$kernel/arch/arm64/boot/dts/allwinner/$dtb_name" /gpu@1800000 clk_rate)" = "$rate"
pvr="$work/pvr-src"; out="$work/pvr-out"; kbuild="$out/target_aarch64/kbuild"
cd "$pvr"
while IFS= read -r -d '' path; do
    mkdir -p "$kbuild/$(dirname "$path")"
    ln -s "$pvr/$path" "$kbuild/$path"
done < <(find . -path ./build -prune -o -name '*.c' -type f -print0)
make -C build/linux/sunxi_linux -j"${JOBS:-7}" KERNELDIR="$kernel" OUT="$out" \
    KERNEL_CC=aarch64-linux-gnu-gcc KERNEL_LD=aarch64-linux-gnu-ld \
    KERNEL_NM=aarch64-linux-gnu-gcc-nm KERNEL_OBJCOPY=aarch64-linux-gnu-objcopy \
    GPU_BUILD_TYPE=release BUILD=release SUPPORT_LINUX_DVFS=0 SUPPORT_PDVFS=0 \
    SUPPORT_DMA_FENCE=1 SUPPORT_BUFFER_SYNC=1
[[ $(modinfo -F vermagic "$kbuild/pvrsrvkm.ko") == "$v "* ]]
tree="$work/boot-candidate"
mkdir -p "$tree/boot" "$tree/usr"
"${km[@]}" INSTALL_MOD_PATH="$tree" INSTALL_MOD_STRIP=1 modules_install
install -D -m644 "$kbuild/pvrsrvkm.ko" "$tree/lib/modules/$v/extra/pvrsrvkm.ko"
aarch64-linux-gnu-strip --strip-debug "$tree/lib/modules/$v/extra/pvrsrvkm.ko"
for name in build source; do
    if [ -L "$tree/lib/modules/$v/$name" ]; then unlink "$tree/lib/modules/$v/$name"; fi
done
depmod -b "$tree" "$v"
mv "$tree/lib" "$tree/usr/lib"
install -m644 "$kernel/arch/arm64/boot/Image" "$tree/boot/Image-$v"
install -m644 "$kernel/.config" "$tree/boot/config-$v"
install -m644 "$kernel/arch/arm64/boot/dts/allwinner/$dtb_name" "$tree/boot/t736-gnome-v$build.dtb"
cd "$work"
tar -C "$tree" -czf "gnome-media-v$build.tar.gz" boot usr
sha256sum "gnome-media-v$build.tar.gz" "$tree/boot/"* > SHA256SUMS
cat SHA256SUMS
