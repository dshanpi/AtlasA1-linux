#!/usr/bin/env python3
"""Compare aligned O_DIRECT reads with GNU dd; never open the SSD for writing."""
import argparse
import fcntl
import json
import mmap
import os
from pathlib import Path
import re
import shutil
import stat
import struct
import subprocess
import time


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--device", default="/dev/nvme0n1")
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    if not re.fullmatch(r"/dev/nvme[0-9]+n[0-9]+", args.device):
        ap.error("expected a whole NVMe namespace, e.g. /dev/nvme0n1")
    if args.output.exists():
        ap.error("output already exists")
    gnu = shutil.which("gnudd") or shutil.which("dd")
    if not gnu or not subprocess.check_output(
            [gnu, "--version"], text=True).splitlines()[0].startswith("dd (coreutils) "):
        ap.error("GNU dd is required for the independent reference read")
    record = {"schema": 1, "kernel": os.uname().release,
              "device": args.device, "reference_tool": gnu,
              "write_test": False, "checks": [], "performance": []}
    fd = os.open(args.device, os.O_RDONLY | os.O_DIRECT | os.O_CLOEXEC)
    try:
        if not stat.S_ISBLK(os.fstat(fd).st_mode):
            raise ValueError("device must be a block device")
        capacity = struct.unpack("Q", fcntl.ioctl(fd, 0x80081272, bytes(8)))[0]
        record["capacity_bytes"] = capacity
        mib, sample_size = 1024 * 1024, 16 * 1024 * 1024
        if capacity < 1024 * mib:
            raise ValueError("namespace must hold at least 1 GiB")
        offsets = sorted({0, min(65536, capacity // mib - 16) * mib})
        for offset in offsets:
            reference = subprocess.check_output([
                gnu, "if=" + args.device, "bs=1M", "count=16",
                "skip=" + str(offset // mib), "iflag=direct", "status=none"])
            if len(reference) != sample_size:
                raise IOError("short reference read")
            for prefill in (False, True):
                matches = []
                for _ in range(8):
                    with mmap.mmap(-1, sample_size,
                                   flags=mmap.MAP_PRIVATE | mmap.MAP_ANONYMOUS) as buf:
                        if prefill:
                            buf[:] = b"\xa5" * sample_size
                        count = os.preadv(fd, [buf], offset)
                        matches.append(count == sample_size and buf[:] == reference)
                record["checks"].append({"offset_bytes": offset,
                    "bytes_per_read": sample_size, "prefill": prefill,
                    "matches_reference": matches})
        with mmap.mmap(-1, mib) as buf:
            for _ in range(2):
                start = time.monotonic()
                for i in range(512):
                    if os.preadv(fd, [buf], i * mib) != mib:
                        raise IOError("short performance read")
                elapsed = time.monotonic() - start
                record["performance"].append({"bytes": 512 * mib,
                    "seconds": elapsed, "MB_s": 512 * mib / elapsed / 1e6})
        record["passed"] = all(all(c["matches_reference"]) for c in record["checks"])
    except Exception as exc:
        record["passed"] = False
        record["error"] = str(exc)
    finally:
        os.close(fd)
    with args.output.open("x", encoding="utf-8") as stream:
        json.dump(record, stream, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    print(json.dumps(record))
    return 0 if record["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
