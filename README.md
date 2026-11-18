# AtlasA1-linux

Linux board patches, kernel configurations, Ethernet support, GPU module integration and Cedar driver changes for the DshanPI AtlasA1.

The v30 candidate adds the boot parameter `t736_cedar_wc.heap_limit_mib` to the v29 512 MiB CMA configuration. Its default is 128 MiB, with a 256 MiB upper bound. The driver keeps retired imported buffers pinned until reboot. The builder takes the matching v29 kernel and PVR source trees. [Build recipe](tools/build_media_v30_candidate.sh) · [Package and module checksums](evidence/media-v30-heap-budget-build-20261118.json)

Armbian integration and pinned upstream revisions are available in [AtlasA1-build](https://github.com/dshanpi/AtlasA1-build).
