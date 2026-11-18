# AtlasA1 Linux 6.18.63 media-v30 sources

This recipe reconstructs the source tree and configuration used for the v30 board tests. Its patch contains the board drivers, device trees, storage timing, Ethernet, USB, power and display adaptations against Linux stable commit `1cdda838e8475edf89b73ff0cc952005dd0b1fa7`. The display port starts from 264 source files in the Tina SDK. The importer verifies each of those files and all 317 resulting board files. The manifest contains the SDK-relative names and SHA-256 values. [Display inputs](tina-display-inputs.json) · [Final source hashes](source-hashes.json)

Run from this repository on a Linux build host with Git, GNU tar, GNU patch and an AArch64 cross-compiler.

```sh
git clone --depth 1 --branch v6.18.63 https://github.com/gregkh/linux.git /tmp/atlas-upstream-linux
python3 tools/prepare_atlas_release_sources.py linux \
  --upstream /tmp/atlas-upstream-linux --tina /path/to/tina \
  --output /tmp/atlas-linux-v30
mkdir /tmp/atlas-kout
cp /tmp/atlas-linux-v30/.config.atlasa1 /tmp/atlas-kout/.config
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- KBUILD_BUILD_VERSION=30
make -C /tmp/atlas-linux-v30 O=/tmp/atlas-kout olddefconfig
make -C /tmp/atlas-linux-v30 O=/tmp/atlas-kout -j"$(nproc)" Image allwinner/t736-gpu-candidate.dtb modules
```

Build the PowerVR module against the same kernel output. The v30 module source has 16 changes relative to the Tina IMG BXM 24.2 kernel DDK. The replay checks the original and patched files.

```sh
python3 tools/prepare_atlas_release_sources.py pvr --tina /path/to/tina --output /tmp/atlas-pvr
T736_PVR_SOURCE=/tmp/atlas-pvr bash tools/build_gpu_module.sh /tmp/atlas-kout /tmp/atlas-pvr-out
```

The v30 media measurements used the boot argument `t736_cedar_wc.heap_limit_mib=256`, a matching PowerVR userspace runtime, and the board-specific Cedar and OMX service configuration. Build timestamps, build host and compiler versions can change binary checksums. [Board-tested kernel recipe](../../../tools/build_media_v30_candidate.sh)
