#!/bin/bash
#
# Make Omarchy's Apple Silicon detection succeed inside a Parallels VM, and record
# the signed bundle release that is already installed, so `omarchy update` runs.
#
# Tested against: Omarchy 4.0.1-mac.1, Parallels Desktop on a Mac Mini M4 Pro,
#                 Arch Linux ARM guest (aarch64), 2026-09-04.
#
# Run as root:  sudo ./scripts/enable-arm-detection.sh
#
# STATUS: written, sandbox-verified, and deliberately NOT APPLIED. `omarchy update`
# works with detection off (verified 2026-09-04), and turning it on switches on
# omarchy-update-asahi-bundle, which will abort the whole update with exit 2 as soon
# as the signed channel advances past sequence 21. Only run this when you actually
# need to move the bundle, and read notes/2026-09-05-apple-silicon-detection.md first.
#
# Replaces the earlier /usr/local/bin/omarchy-hw-apple-silicon PATH shim, which
# cannot work: omarchy-migrate calls $OMARCHY_PATH/bin/omarchy-hw-apple-silicon by
# absolute path, and /usr/share/omarchy/bin precedes /usr/local/bin in PATH anyway.
# The stock detector honours OMARCHY_PROC_ROOT, so no shim is needed at all.

set -euo pipefail

vm_root=/var/lib/omarchy/vm-root
state_file=/var/lib/omarchy/asahi-quattro-release

# Verified against the signed channel descriptor on 2026-09-04. The installed
# bundle packages already provide this source commit, which is why the state file
# below is a true record and not a forgery.
channel_sequence=21
channel_tag=asahi-quattro-5939caf7
channel_source=5939caf720c1fb7e137d57ab87c0182f2132e5a3

(( EUID == 0 )) || { echo "Run this with sudo." >&2; exit 1; }
[[ $(uname -m) == aarch64 ]] || { echo "This is only for aarch64 guests." >&2; exit 1; }

# 1. A fake root carrying just the device-tree node the two independent checks read.
#    OMARCHY_PROC_ROOT appends /device-tree/compatible; OMARCHY_ASAHI_ROOT appends
#    /proc/device-tree/compatible. One tree satisfies both.
install -d -o root -g root -m 0755 "$vm_root" "$vm_root/proc" "$vm_root/proc/device-tree"
printf 'apple,parallels-vm' >"$vm_root/proc/device-tree/compatible"
chown root:root "$vm_root/proc/device-tree/compatible"
chmod 0644 "$vm_root/proc/device-tree/compatible"

# 2. Point both variables at it for every login session (pam_env reads this file).
tmp=$(mktemp)
grep -vE '^(OMARCHY_PROC_ROOT|OMARCHY_ASAHI_ROOT)=' /etc/environment >"$tmp" || true
cat >>"$tmp" <<EOF
OMARCHY_PROC_ROOT=$vm_root/proc
OMARCHY_ASAHI_ROOT=$vm_root
EOF
chmod --reference=/etc/environment "$tmp"
chown --reference=/etc/environment "$tmp"
mv "$tmp" /etc/environment

# 3. Record the installed bundle release. omarchy-update-asahi-bundle compares the
#    signed channel against this file; with it present and current, the script
#    reports "up to date" and exits 0 BEFORE reaching the gates this VM can never
#    pass (linux-asahi installed, /boot/vmlinuz-linux-asahi, [asahi-alarm], iwd).
installed_source=$(pacman -Qi omarchy-dev 2>/dev/null |
  sed -n 's/.*omarchy-quattro-bundle=\([0-9a-f]\{40\}\).*/\1/p' | head -1)
if [[ $installed_source != "$channel_source" ]]; then
  echo "Refusing to write $state_file." >&2
  echo "  installed bundle source: ${installed_source:-none}" >&2
  echo "  expected:                $channel_source" >&2
  echo "Re-verify against the signed channel before recording a release." >&2
  exit 1
fi
printf 'format=1\nsequence=%s\ntag=%s\nsource_commit=%s\n' \
  "$channel_sequence" "$channel_tag" "$channel_source" >"$state_file"
chown root:root "$state_file"
chmod 0644 "$state_file"

# 4. Retire the superseded shim and its fake proc root.
rm -f /usr/local/bin/omarchy-hw-apple-silicon
rm -rf /var/lib/omarchy/vm-proc

echo "Done. Open a new login session (or export both vars) and verify:"
echo "  OMARCHY_PROC_ROOT=$vm_root/proc /usr/bin/omarchy-hw-apple-silicon; echo \$?   # want 0"
echo "  OMARCHY_ASAHI_ROOT=$vm_root omarchy-update-asahi-bundle --check; echo \$?     # want 1 (up to date)"
