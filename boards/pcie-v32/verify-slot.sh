#!/bin/sh
# Read-only by default. --rescan requests a scan of this host bridge only.
set -eu
case "${1:-}" in
    "" | --rescan) ;;
    *) echo "usage: $0 [--rescan]" >&2; exit 2 ;;
esac
host=/sys/bus/platform/devices/6000000.pcie
port=/sys/bus/pci/devices/0000:00:00.0
printf 'Kernel %s\n' "$(uname -r)"
test -d "$host" || { echo "PCIe platform device missing"; exit 1; }
test -L "$host/driver" || { echo "PCIe platform driver unbound"; exit 1; }
printf 'Platform driver %s\n' "$(basename "$(readlink "$host/driver")")"
test -d "$port" || { echo "PCI root port missing"; exit 1; }
case "$(readlink -f "$port")" in
    "$(readlink -f "$host")"/*) ;;
    *) echo "Unexpected PCI root port owner"; exit 1 ;;
esac
class=$(cat "$port/class")
case "$class" in 0x0604*) ;; *) echo "Unexpected bridge class $class"; exit 1;; esac
printf 'Root port 0000:00:00.0 vendor=%s device=%s class=%s\n' \
    "$(cat "$port/vendor")" "$(cat "$port/device")" "$class"
if [ "${1:-}" = --rescan ]; then
    # The root port scans its downstream bus. Do not rescan unrelated buses.
    printf '1\n' >"$port/rescan"
    printf '%s\n' "Root port rescan completed"
fi
for item in current_link_speed current_link_width max_link_speed max_link_width; do
    if [ -r "$port/$item" ]; then
        printf '%s = %s\n' "$item" "$(cat "$port/$item")"
    fi
done
count=0
for dev in /sys/bus/pci/devices/*; do
    [ -d "$dev" ] || continue
    case "$(readlink -f "$dev")" in
        "$(readlink -f "$port")"/*)
            printf 'Downstream %s vendor=%s device=%s class=%s\n' \
                "$(basename "$dev")" "$(cat "$dev/vendor")" \
                "$(cat "$dev/device")" "$(cat "$dev/class")"
            count=$((count + 1))
            ;;
    esac
done
printf 'Downstream device count %s\n' "$count"
if [ "$count" -eq 0 ]; then
    echo "Empty-slot host check passed; downstream link and I/O unverified."
else
    echo "Downstream device enumeration observed; functional I/O requires a device-specific test."
fi
