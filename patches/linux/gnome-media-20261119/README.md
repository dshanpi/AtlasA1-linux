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

Build from pinned upstream Linux and the configured Tina SDK using the normal
source replay checks, then these explicit candidate deltas:

```sh
bash tools/build_gnome_media_candidate.sh /src/linux /src/tina /tmp/gnome-v36
bash tools/build_gnome_media_candidate.sh /src/linux /src/tina /tmp/gnome-v37 --gpu600
bash tools/build_gnome_media_candidate.sh /src/linux /src/tina /tmp/gnome-v39 --rcq-poll
bash tools/build_gnome_media_candidate.sh /src/linux /src/tina /tmp/gnome-v40 --cedar-import
```

The output archive uses `usr/lib/modules`, preserving merged-/usr systems.
Install into a staging directory first, then copy the versioned module directory
and boot files, run depmod/mkinitramfs, and use a one-shot boot. Retain the current
default kernel and independent serial recovery. Never replace `/lib` when
installing a candidate archive.

The earlier v35 experiment armed an event *after* RCQ completion, adding a refresh
of latency; its measured 1080p60 rate fell to about 27.5 fps. That rejected patch
is not included here. v37's first DTB incorrectly retained 400 MHz and PVR rejected
initialization; the patch here includes the required `clk_rate = <600000000>` fix.

See [GNOME media results](../../../docs/GNOME_MEDIA.md) and raw evidence for the
measured scope and remaining failures. A successful build or boot does not imply
60 fps playback, HDMI audio, video encoding or full hardware acceptance.
