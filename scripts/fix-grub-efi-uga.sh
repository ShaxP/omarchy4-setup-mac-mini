#!/usr/bin/env bash
# Remove the `efi_uga.mod not found` boot pause on Arch Linux ARM under UEFI.
#
# Tested against: Omarchy 4.0.1-mac.1, Arch Linux ARM aarch64, Parallels on Apple Silicon.
# Run: after every `grub` package update, which restores /etc/grub.d/00_header.
#
# efi_uga is GRUB's legacy UEFI Universal Graphics Adapter driver. It is an x86 module
# and is NOT shipped for arm64, but 00_header emits `insmod efi_uga` unconditionally for
# EFI platforms, so GRUB stops on every boot waiting for a keypress. efi_gop is the
# modern protocol, is present, and is all this platform needs.
#
# Idempotent: safe to run repeatedly, does nothing if already patched.
set -euo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || exec sudo "$0" "$@"

HEADER=/etc/grub.d/00_header
CFG=/boot/grub/grub.cfg

# grub-mkconfig executes EVERY executable file in /etc/grub.d/, and cp preserves the
# execute bit - so a backup left there is run as a generator and re-emits the very block
# this script removes. That failure looks like the patch silently not working.
stray=$(find /etc/grub.d -maxdepth 1 -type f -perm -u+x \
  \( -name '*.bak' -o -name '*.orig' -o -name '*.save' -o -name '*~' \
     -o -name '*.pacnew' -o -name '*.pacsave' \) 2>/dev/null || true)
if [[ -n $stray ]]; then
  echo "ERROR: executable backup files in /etc/grub.d/ - grub-mkconfig will run these:"
  printf '  %s\n' $stray
  echo "Move them out of /etc/grub.d/ (or chmod -x them) and re-run."
  exit 1
fi

if grep -qE '^[[:space:]]*insmod efi_uga[[:space:]]*$' "$HEADER"; then
  backup="/root/00_header.$(date +%Y%m%d-%H%M%S).bak"   # NOT in /etc/grub.d
  cp -a "$HEADER" "$backup"
  sed -i '/^[[:space:]]*insmod efi_uga[[:space:]]*$/d' "$HEADER"
  echo "Patched $HEADER (backup: $backup)"
else
  echo "$HEADER already clean"
fi

if ! grep -qE '^[[:space:]]*insmod efi_gop[[:space:]]*$' "$HEADER"; then
  echo "WARNING: no 'insmod efi_gop' left in $HEADER - graphics may not initialise."
fi

echo "Regenerating $CFG ..."
grub-mkconfig -o "$CFG"

n=$(grep -c 'efi_uga' "$CFG" || true)
if [[ $n -eq 0 ]]; then
  echo "OK - no efi_uga references remain. The boot pause is gone after the next reboot."
else
  echo "FAILED - $CFG still has $n efi_uga reference(s)."
  echo "Check: grep -rn 'efi_uga' /etc/grub.d/   (something there is still emitting it)"
  exit 1
fi
