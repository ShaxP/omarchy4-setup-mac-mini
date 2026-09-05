#!/usr/bin/env bash
# Restore Arch Linux ARM pacman config after Omarchy overwrites it with x86 mirrors.
#
# Tested against: Omarchy 4.0.0-mac.*, Arch Linux ARM aarch64, Parallels on Apple Silicon.
# Run: as a RECOVERY tool, when pacman is actually broken (404s, `could not find
# database`, or makepkg reporting missing dependencies that do exist).
#
# NOT needed after `omarchy update`. Verified 2026-09-05: nothing in the update path
# calls omarchy-refresh-pacman, and an update left mirrorlist and pacman.conf
# untouched. It is Omarchy's install/ scripts and menu that rewrite pacman config.
#
# NOTE: this REPLACES /etc/pacman.conf wholesale. If you add your own IgnorePkg or
# similar lines, add them to write_pacman_conf() below or they will be lost.
# NOTE: SigLevel = Never disables package signature verification. It is required to
# work around broken signing in the archboot ARM environment. Do not carry this
# config outside this throwaway VM.
set -euo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || exec sudo "$0" "$@"

MIRROR='Server = http://mirror.archlinuxarm.org/$arch/$repo'

write_mirrorlist() { printf '%s\n' "$MIRROR" > "$1"; }

write_pacman_conf() {
  cat > "$1" <<'CONF'
[options]
HoldPkg           = pacman glibc
Architecture      = auto
CheckSpace
ParallelDownloads = 5
SigLevel          = Never
LocalFileSigLevel = Never

# Temporary hold, added 2026-09-04. Arch Linux ARM bumped aquamarine to
# libaquamarine.so=14 without rebuilding hyprland/hyprtoolkit, which still require
# so=13, so aquamarine 0.15.0 is uninstallable and blocks the whole -Syu.
# REMOVE once `pacman -Si hyprland | grep aquamarine` reports so=14.
IgnorePkg         = aquamarine

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[alarm]
Include = /etc/pacman.d/mirrorlist

[aur]
Include = /etc/pacman.d/mirrorlist
CONF
}

write_mirrorlist /etc/pacman.d/mirrorlist
write_pacman_conf /etc/pacman.conf

# Omarchy's own scripts copy these templates over your live config during setup
# and during `omarchy update`. Poison them with the ARM config too.
tpl=/usr/share/omarchy/default/pacman
if [[ -d $tpl ]]; then
  for f in pacman-stable.conf pacman-edge.conf pacman-rc.conf; do
    if [[ -e $tpl/$f ]]; then write_pacman_conf "$tpl/$f"; fi
  done
  for f in mirrorlist-stable mirrorlist-edge mirrorlist-rc; do
    if [[ -e $tpl/$f ]]; then write_mirrorlist "$tpl/$f"; fi
  done
  echo "Patched Omarchy templates in $tpl"
else
  echo "No $tpl yet (Omarchy not installed) - live config only"
fi

echo "Verifying pacman can reach the ARM repos..."
if pacman -Sy >/dev/null 2>&1; then echo "OK"; else echo "FAILED - inspect /etc/pacman.conf"; exit 1; fi
