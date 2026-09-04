# Omarchy 4 on Apple Silicon, in Parallels

A worked, phase-by-phase checklist for installing **Omarchy 4 (Quattro)** in a
**Parallels Desktop** VM on an Apple Silicon Mac — written while actually doing it on a
**Mac Mini M4 Pro**, with every failure encountered recorded alongside the fix.

**→ [The checklist](notes/2026-09-03-omarchy4-parallels-checklist.md)**

## Why this exists

Official Omarchy is **x86_64 only**. The ISO will not boot on Apple Silicon, where
Parallels can run arm64 guests only. There is no supported path, so this one goes:

1. **Arch Linux ARM** as the base, from an arm64 **archboot** ISO
2. Omarchy's **aarch64 package bundle** installed on top

Result on this run: **Omarchy 4.0.1-mac.1**, 128 GB SATA disk, 8 CPUs / 32 GB RAM.
Desktop, terminal and keybindings all working.

## What's here

| | |
|---|---|
| [`notes/`](notes/) | The install checklist — 9 phases, every command, every failure and its cause |
| [`notes/omarchy-update-checklist.md`](notes/omarchy-update-checklist.md) | How to run `omarchy update` without breaking the VM, and why it breaks |
| [`scripts/fix-pacman-arm.sh`](scripts/fix-pacman-arm.sh) | Restores the Arch Linux ARM pacman config that Omarchy's scripts overwrite with x86 mirrors |
| [`scripts/fix-grub-efi-uga.sh`](scripts/fix-grub-efi-uga.sh) | Removes the `efi_uga.mod not found` pause that stops every boot on a keypress |

## Ongoing maintenance

Two upstream files get restored by routine package updates, so both problems come back
**every time** that update runs — for the life of the VM. Neither is a one-time fix, and
nothing is wrong when they reappear.

| After | Symptom | Fix |
|---|---|---|
| `omarchy update` | `could not find database`, 404s, or `makepkg` reporting dependencies that are in fact available | `sudo ~/fix-pacman-arm.sh` |
| a `grub` update | Every boot pauses on ``efi_uga.mod' not found`` | `sudo ~/fix-grub-efi-uga.sh` |

Both scripts are idempotent and print `OK` on success, so running both after any update
costs nothing and rules out the two known causes at once.

**The pacman one may be avoidable.** It turns out `omarchy-refresh-pacman` explicitly
refuses to touch an Apple Silicon system — the config only gets overwritten because
Parallels exposes no device tree, so Omarchy's hardware detection cannot tell it is on
ARM and takes the x86 path. A small shim making that detection succeed appears to fix it
at the source. See the [update checklist](notes/omarchy-update-checklist.md). Details, symptoms and manual
steps are in [the checklist](notes/2026-09-03-omarchy4-parallels-checklist.md#ongoing-maintenance--two-things-that-come-back).

## The four things that actually cost time

None of these appear in the source guide. All are documented with their exact symptoms:

1. **The VM's disk was `disabled`, not missing.** `prlctl list -i` shows `hdd0 (-)`. From
   inside the guest this is indistinguishable from a missing disk — the AHCI controller
   enumerates fine and the port is simply empty — so it cannot be diagnosed from there.
2. **archboot's NIC starts `DOWN`, and its sshd refuses password auth.** Neither is
   mentioned anywhere; together they make the "SSH in and paste the rest" approach
   impossible until both are fixed.
3. **`$VMUSER` does not survive into the chroot.** `useradd -m -G wheel ""` fails
   silently mid-paste and the install completes with *no user account*, surfacing two
   steps later as an SSH `Permission denied` that looks exactly like a wrong password.
4. **Omarchy re-breaks pacman before the source builds.** Five of seven packages then
   fail with `Could not resolve all dependencies`, naming packages that are in fact
   available — pacman just cannot read any database while `[multilib]` and `[omarchy]`
   are in the config.

## Known limitations

- `omarchy update` restores the x86 pacman templates every time. Re-run the fix script.
- **No Parallels Tools on ARM Arch:** no clipboard sync with macOS, no dynamic
  resolution (set it via a kernel parameter), single display only.
- x86-only apps from Omarchy's catalog (Spotify, 1Password, …) cannot be installed.
- The VM as described runs with `SigLevel = Never` and no disk encryption. It is a
  disposable experiment, not a place for real credentials.

## Credit

- [u/antipop2's r/omarchy guide](https://www.reddit.com/r/omarchy/comments/1vrpp7b/40_running_in_parallels/) — the source this is based on, done on an M2 Max
- [maralcbr/omarchy-mx-mac](https://github.com/maralcbr/omarchy-mx-mac) and
  [maralcbr/omarchy-pkgs](https://github.com/maralcbr/omarchy-pkgs) — the aarch64
  packages and signed release channel that make any of this possible

Unsupported by everyone involved: Omarchy says no M-series Macs, omarchy-mx-mac targets
bare-metal Asahi rather than VMs. If it breaks, you own it.
