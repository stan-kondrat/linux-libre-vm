#!/bin/sh
# Boot diagnostics — runs during stage 1 when boot.diag=1 on kernel cmdline
# All binaries are in /bin

# Skip diagnostics unless explicitly requested
if ! grep -q 'boot.diag' /proc/cmdline 2>/dev/null; then
  exit 0
fi

PATH=/bin

echo "=== Boot Diagnostics ==="
echo "Hostname: $(cat /proc/sys/kernel/hostname)"
echo "Kernel: $(uname -r)"
echo "Arch: $(uname -m)"
echo "Uptime: $(cat /proc/uptime | cut -d' ' -f1) seconds"
echo ""
echo "--- Mounts ---"
mount | grep -E 'proc|sys|dev'
echo ""
echo "--- Memory ---"
cat /proc/meminfo | grep -E 'MemTotal|MemFree|MemAvailable'
echo ""
echo "--- Processes ---"
ps -A | wc -l
echo ""
echo "--- Basic commands ---"
echo -n "  ls /bin: " && ls /bin | wc -l && echo " binaries"
echo -n "  whoami: " && whoami
echo -n "  pwd: " && pwd
echo ""
echo "--- Network ---"
ip addr show lo 2>/dev/null | grep inet
echo "--- DHCP Test ---"
for iface in /sys/class/net/*; do
  name=$(basename "$iface")
  [ "$name" = "lo" ] && continue
  echo "  $name: bringing up..."
  ip link set "$name" up 2>/dev/null || true
  dhcpcd -t 3 "$name" 2>&1 | head -3
  ip addr show "$name" 2>/dev/null | grep 'inet ' || echo "  $name: no IP"
done
echo "=== Diagnostics Complete ==="
