# GNOME media candidates

These patches are experiments against the verified v30 Linux/PVR source replay.
They are **not** applied by the default Armbian image recipe.

- `v36-vblank.patch`: publish the flip event before RCQ submission, complete it
  in the existing vblank IRQ, and keep old framebuffers until flip completion.
  Warm 1080p60 measured about 53.1 presented fps; this is still below acceptance.
- `v37-gpu600-linux.patch` and `v37-gpu600-pvr.patch`: additionally select the
  existing PERI0/2 600 MHz source, describe it to CCF, and keep the genpd,
  device-tree `clk_rate` and PVR fixed-rate configuration consistent. The
  original PERI400 clock remains available. Shared PLLs and voltage are unchanged.
  Tina's T736 OPP table specifies 600 MHz at 800 mV; the board measured 900 mV.
  This is not a DVFS or thermal-management implementation.
  On hardware, warm 1080p60 remained about 53.0 fps (versus 53.1 at 400 MHz).
  It is retained as an experiment, not selected as a default performance fix.
- `v38-rcq-poll.patch`: expose a bounded 50..2000 us RCQ completion polling
  interval, keeping the original 2000 us default. v38 additionally enabled
  dynamic preemption (default none); booting Xorg produced kernel Oops and the
  candidate was rejected before playback testing. v39 isolates the polling
  parameter with the original non-preemptible kernel configuration.
- `v40-cedar-import.patch`: preserve the VE identity mapping while creating
  separate DMA mappings for GPU/display importers. This is only the kernel
  prerequisite for sharing decoder output; it does not implement frame leases,
  release fences, browser transport or an end-to-end zero-copy player.
- `v41-prime-scanout.patch`: use DMA-only PRIME import for scanout instead of
  requiring an exporter CPU vmap. Native dumb allocations remain CPU-mapped.
  This eliminated the repeated PowerVR `Failed to vmap PRIME buffer` errors,
  but warm 1080p60 still measured 51.5 presented fps; it is not a 60fps fix.
- `v42-trace-api.patch` and `v42-pvr-trace-api.patch`: update display/PVR
  tracepoint string assignment for Linux 6.18. The v42 candidate enables
  function/event tracing with the same non-preemptible configuration as v41.
  Tracing is a diagnostic option, not a performance improvement.
- `v46-mmc-tuning-log.patch`: retain the first expected bad-tap DMA snapshot
  during each tuning pass. Report every error outside the existing recovery
  classifier. Keep tuning, verification, DMA ownership and error handling intact.
  v47 additionally sets the default console loglevel to 5. Kernel information
  remains in the log buffer; the UART displays warnings and errors.

Build from pinned upstream Linux and the configured Tina SDK using the normal
source replay checks, then these explicit candidate deltas:

```sh
bash tools/build_gnome_media_candidate.sh /src/linux /src/tina /tmp/gnome-v36
bash tools/build_gnome_media_candidate.sh /src/linux /src/tina /tmp/gnome-v37 --gpu600
bash tools/build_gnome_media_candidate.sh /src/linux /src/tina /tmp/gnome-v39 --rcq-poll
bash tools/build_gnome_media_candidate.sh /src/linux /src/tina /tmp/gnome-v40 --cedar-import
bash tools/build_gnome_media_candidate.sh /src/linux /src/tina /tmp/gnome-v41 --prime-scanout
bash tools/build_gnome_media_candidate.sh /src/linux /src/tina /tmp/gnome-v42 --display-trace
bash tools/build_gnome_media_candidate.sh /src/linux /src/tina /tmp/gnome-v46 --boot-log
bash tools/build_gnome_media_candidate.sh /src/linux /src/tina /tmp/gnome-v47 --boot-fast
```

The output archive uses `usr/lib/modules`, preserving merged-/usr systems.
Install into a staging directory first, then copy the versioned module directory
and boot files, run depmod/mkinitramfs, and use a one-shot boot. Retain the current
default kernel and independent serial recovery. Never replace `/lib` when
installing a candidate archive.

For compressed kernel loading, run AtlasA1-build's `tools/prepare_atlasa1_boot_kernel.py` with
the versioned Image and a new output path. It validates the ARM64 header,
checks the gzip roundtrip and preserves the uncompressed input. The source
U-Boot supports this format. Install `config/initramfs/50-atlasa1-boot-status.conf`
under `/etc/systemd/system.conf.d/` to display failed systemd jobs while retaining
the journal. See [boot measurements](https://github.com/dshanpi/AtlasA1-build/blob/main/docs/BOOT_SPLASH.md)
for measured scope and results. The helper and rootfs configuration live in AtlasA1-build.

The earlier v35 experiment armed an event *after* RCQ completion, adding a refresh
of latency; its measured 1080p60 rate fell to about 27.5 fps. That rejected patch
is not included here. v37's first DTB incorrectly retained 400 MHz and PVR rejected
initialization; the patch here includes the required `clk_rate = <600000000>` fix.

See [GNOME media results](../../../docs/GNOME_MEDIA.md) and raw evidence for the
measured scope and remaining failures. A successful build or boot does not imply
60 fps playback, HDMI audio, video encoding or full hardware acceptance.
