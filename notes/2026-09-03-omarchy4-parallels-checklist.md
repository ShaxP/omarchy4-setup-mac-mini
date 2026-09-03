# Omarchy 4 (Quattro) on Mac Mini M4 Pro / Parallels — working checklist

Date: 2026-09-03
Target: Omarchy 4.0.x-mac.* on Arch Linux ARM (aarch64) in Parallels Desktop
Installed: **4.0.1-mac.1** (guide was written against 4.0.0-mac.6; no differences hit so far)
Host: Mac Mini M4 Pro

Based on [u/antipop2's r/omarchy guide](https://www.reddit.com/r/omarchy/comments/1vrpp7b/40_running_in_parallels/)
(done on an M2 Max), which in turn borrows from
[maralcbr/omarchy-mx-mac](https://github.com/maralcbr/omarchy-mx-mac) and
[maralcbr/omarchy-pkgs](https://github.com/maralcbr/omarchy-pkgs).

Lines marked **[+]** are changes from the original guide: things reordered or done
up front so you hit the known failures once instead of discovering them mid-install.

Officially unsupported by everyone: Omarchy says no M-series Macs, omarchy-mx-mac
says no VMs. Treat the VM as disposable and snapshot often.

---

## Which machine am I on?

Commands run in one of three places and the notes mark them where it is not obvious:

- **Mac** — `prlctl`, `scp`, `ssh`. Run from this repo's directory when a path is
  relative (`scripts/fix-pacman-arm.sh` only exists here, not in the VM).
- **VM console** — the Parallels window. Needed only before SSH works, and when the
  network is down.
- **VM over SSH** — everything else.

`VMUSER` / `VMHOST` are shell variables, so they exist only in the shell you exported
them in. Export them on **both** machines, or use literals for one-off commands.

## 0. Fill these in first

Set these once in each shell you work from. Every command below uses them, so you
should be able to paste rather than adapt.

```bash
export VMUSER=shahram                 # Linux username inside the VM
export VMRES=5120x1440@120            # see "Display" below - the @120 is likely ignored
export VMHOST=                        # VM IP, filled in during Phase 2
```

**[+] Take a Parallels snapshot at the end of every phase.** The expensive failures
in this install are the ones that force you back to Phase 1. A snapshot costs seconds.
Name them `phase-1-base`, `phase-4-bundle`, etc.

---

## Phase 1 — VM and Arch Linux ARM base

ISO: latest **archboot aarch64** from `release.archboot.com/aarch64/latest`
(EU mirror: `release.archboot.eu`). Not the Omarchy ISO, not the stock Arch ISO —
both are x86_64 only and will not boot.

Parallels: new VM from the ISO, type **Other Linux**. The original author used
4 CPUs / 16 GB RAM / 64 GB disk on an M2 Max; on an M4 Pro be more generous.
**Used here: 128 GB disk** — Phase 8 builds ten packages from source with `makepkg`,
and the build trees plus the pacman cache eat more than 64 GB comfortably allows.

### Disk: attach one, on SATA

**Confirmed failure on the Mac Mini run: the VM was created with no hard disk at all.**
This is the first thing to check, ahead of any driver theory. In Parallels: Configure >
Hardware, and make sure a **Hard Disk** device actually exists (128 GB, **SATA 0:1**,
expanding). Creating a VM from an ISO does not always add one.

**Boot order:** during the install, **CD/DVD first, Hard Disk second** — the ISO has to
win and the empty disk falls through harmlessly. After step 7, flip to **Hard Disk
first** and disconnect the ISO. Leave Network/PXE out of the list entirely; it only adds
a boot timeout.

Leave **Enable TRIM** checked. With an expanding image, TRIM is how the guest tells
Parallels which blocks it freed, so the `.hdd` on the Mac can shrink instead of only
ever growing. See `fstrim.timer` in Phase 6 for the guest side that makes it work.

If Parallels offers IDE, still prefer SATA: IDE/PATA emulation is a legacy x86
chipset device whose Linux drivers (`ata_piix` and friends) are x86 kernel config
options and are generally not built into aarch64 kernels. SATA also gives you
`/dev/sda`, which is what every command in this checklist assumes.

### Fastest check: ask Parallels, not the guest

The GUI can show a fully configured 128 GB disk that the VM is not actually using.
Read the real config from the Mac instead — one command settles it:

```bash
prlctl list -i "Omarchy 4" | grep -E 'hdd0|cdrom0'
```

```
hdd0   (-) sata:0  image='.../Omarchy 4-0.hdd' type='expanded' 131072Mb   <- DISABLED
cdrom0 (+) sata:1  image='.../archboot-...iso'
```

**`(-)` means the device is disabled, `(+)` means enabled.** This was the actual fault on
the Mac Mini run: the disk existed, was the right size, sat on the right port, and was
switched off. The guest saw an empty SATA port and no amount of guest-side debugging
would have shown why. Fix it with the VM stopped:

```bash
prlctl set "Omarchy 4" --device-set hdd0 --enable --connect
prlctl list -i "Omarchy 4" | grep hdd0        # must now read (+)
```

A disabled `hdd0` also makes its location unavailable in the GUI dropdown — `hdd0`
still owns `sata:0`, so `SATA 0:0` is not offered as a free slot for a new disk. If the
location you want is greyed out, suspect this rather than adding a second disk.

Other things this output settles at a glance: whether `hdd0` exists at all, its
interface (`sata:` vs `ide:`), and its size in Mb (`131072Mb` = 128 GB). An image of a
megabyte or so is a normal empty expanding disk, not a broken one.

### Before partitioning, confirm the disk is really there

Run this in the archboot shell:

```bash
lsblk
dmesg | grep -iE 'ahci|ata[0-9]|nvme|Direct-Access'
```

Healthy output has a `SATA link up` line for the disk **and** one for the DVD, plus
`sda` in `lsblk`. Interpretation:

- `sda` present at the size you configured (128G here) → good, proceed.
- **`lsblk` shows only `sr0` and `zram0`**, and `dmesg` shows the AHCI controller found
  (`ahci PRL4010:00`, `scsi host0..5`) with exactly one `ata2: SATA link up` for the
  `Virtual DVD-ROM` and `SATA link down` on every other port → **no disk is attached.**
  This is not a driver problem: SATA clearly works, it enumerated the DVD over the same
  controller. Power off and add a Hard Disk in Parallels. `zram0` mounted at `/` is
  archboot's normal RAM root, not your disk.
- `nvme0n1` instead → works fine, but **substitute `/dev/nvme0n1` for `/dev/sda`, and
  `p1`/`p2`/`p3` for the partition suffixes** (`/dev/nvme0n1p1`, not `/dev/nvme0n11`).
- `vda` → virtio. Substitute `/dev/vda` / `vda1`.
- Controller not found at all (no `ahci` lines) → then it is the IDE case above; switch
  the disk to SATA in Parallels.

> Adding the disk requires a power-off, and rebooting gives you a fresh live
> environment — the network and sshd setup below is lost and must be redone. Check for
> the disk **before** investing in the SSH setup.

1. Boot the ISO. A text-mode setup wizard starts — **press Ctrl+C to exit it.** Its
   automated install does not work in this VM. Everything below is by hand.

   **[+] Get SSH up in the live environment right now, before partitioning.** There is
   no clipboard into the Parallels console, and every command from here on is long.
   Archboot is designed for remote installs, so `openssh` is already on the ISO:

   **Network first — the interface comes up DOWN.** Confirmed on this VM: archboot does
   not bring the NIC up on its own, so there is no address until you do it by hand. This
   is the actual first command, not a troubleshooting step:

   ```bash
   ip link                           # find the NIC; on Parallels it is usually enp0s5
   ip link set enp0s5 up             # <- it starts DOWN. This is the bit that is missing.
   systemctl start systemd-networkd systemd-resolved
   sleep 3
   ip -4 addr show scope global      # expect 10.211.55.x
   ```

   Still no address after that? Run a DHCP client directly, whichever exists:
   `dhcpcd enp0s5`, or `dhclient enp0s5`.

   Verify in two stages, because they fail differently:

   ```bash
   ping -c2 1.1.1.1                  # raw connectivity
   ping -c2 archlinux.org            # DNS
   ```

   - Address but no ping to `1.1.1.1` → routing. Check `ip route` for a default via
     `10.211.55.1`; add it with `ip route add default via 10.211.55.1` if missing.
   - `1.1.1.1` pings but names do not resolve → DNS only.
     `echo 'nameserver 1.1.1.1' > /etc/resolv.conf`.
   - `ip link` shows **only `lo`** → no NIC is attached to the VM at all. Fix it in
     Parallels (Actions > Configure > Hardware > Network, enabled, Shared Network), not
     in the guest. Nothing is installed yet, so power off and reboot the ISO freely.

   **Then bring up SSH.** This took several rounds on the first run — archboot's sshd
   does **not** accept password logins out of the box. Do all of it before testing:

   ```bash
   passwd                            # sshd refuses empty-password logins
   ssh-keygen -A                     # host keys, if missing

   # archboot ships PasswordAuthentication no. Find where it is set:
   grep -rniE '^\s*(PasswordAuthentication|PermitRootLogin)' \
     /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null
   # ...then flip it in whichever file that names:
   sed -i 's,^\s*PasswordAuthentication.*,PasswordAuthentication yes,' <that-file>
   sed -i 's,^\s*PermitRootLogin.*,PermitRootLogin yes,'               <that-file>

   systemctl restart sshd
   ```

   **Verify the effective config, not the file** — `sshd_config` usually starts with
   `Include /etc/ssh/sshd_config.d/*.conf`, OpenSSH takes the **first** value it obtains
   for a directive, so an edit to the main file can be silently overridden by a drop-in:

   ```bash
   sshd -T | grep -iE 'permitrootlogin|passwordauthentication|^port'
   ss -tlnp | grep -i ssh            # confirm 0.0.0.0:22, not 127.0.0.1:22
   ```

   All three must read `yes` / `yes` / `22`. Do not trust `grep` on the config file.
   If the grep above found nothing to edit, a drop-in that sorts first wins:

   ```bash
   printf 'PasswordAuthentication yes\nPermitRootLogin yes\n' > /etc/ssh/sshd_config.d/00-root.conf
   systemctl restart sshd
   ```

   Then from the Mac: `ssh root@<address>`.

   All of this is throwaway — it configures the live ISO's sshd, not the installed
   system's. The installed system (step 6) is stock and needs none of it.

   **Reading the failures:**

   - `Permission denied (publickey).` → password auth still off. Re-check `sshd -T`.
   - `Permission denied (publickey,password,...)` after a prompt → auth is on, the
     password is wrong or root has none. Run `passwd`.
   - `Connection refused` → nothing listening. Check `ss -tlnp` and `journalctl -u sshd -n 30`.
   - `No route to host` → seen once on the first run and never fully explained. ARP was
     healthy (`arp -n <ip>` complete, `00:1c:42` Parallels OUI) and the guest had no
     firewall (`iptables -S` all-ACCEPT, no rules), yet it failed; it cleared after the
     sshd fixes above. If you hit it: confirm `ping -c3 <ip>` from the Mac, check
     `arp -n <ip>` is not `(incomplete)`, then just retry once networking has settled.
   - No `sshd` binary? `pacman -Sy --noconfirm openssh` — run the step 4 `SigLevel` fix
     first if it errors on signatures.
   - Curses programs (`cfdisk`) unhappy over SSH? `export TERM=xterm-256color`.

   This session ends at the step 7 reboot — it is the live ISO's sshd, not the installed
   system's. The installed system comes back with sshd enabled (step 6) on the same
   address, and SSH will warn about a changed host key because it genuinely is a
   different machine: `ssh-keygen -R <address>` on the Mac.

2. Partition: `cfdisk /dev/sda`, label type **gpt**.

   | Partition | Size | Type |
   |---|---|---|
   | `/dev/sda1` | 512M | EFI System |
   | `/dev/sda2` | 8G | Linux swap |
   | `/dev/sda3` | rest | Linux root (ARM-64) |

   EFI and swap stay these sizes regardless of disk size; root just absorbs the rest.

3. Format and mount:

   ```bash
   mkfs.fat -F32 /dev/sda1
   mkswap /dev/sda2 && swapon /dev/sda2
   mkfs.ext4 /dev/sda3
   mount /dev/sda3 /mnt
   mount --mkdir /dev/sda1 /mnt/boot
   ```

4. **Signature verification is broken in the archboot ARM environment** — pacman fails
   with signature errors. There are several `SigLevel` lines (one under `[options]`,
   one per repo). Fix all of them:

   ```bash
   sed -i 's/^\s*SigLevel.*/SigLevel = Never/' /etc/pacman.conf
   ```

5. Install the base. `terminus-font` is **required** here — without it kernel image
   generation fails. `mkinitcpio` errors during this step are expected, ignore them.

   ```bash
   pacstrap /mnt base base-devel linux grub efibootmgr networkmanager git terminus-font nano openssh
   genfstab -U /mnt >> /mnt/etc/fstab
   arch-chroot /mnt
   ```

   **[+]** `openssh` added here so Phase 2 needs no network round-trip.

6. Inside the chroot. **[+] `export TERM=linux` first** or nano will not start:

   ```bash
   export TERM=linux
   export VMUSER=shahram     # [+] MUST be re-exported: the outer shell's value does
                             #     not reliably survive into the chroot
   sed -i 's/^\s*SigLevel.*/SigLevel = Never/' /etc/pacman.conf   # again, new system
   ln -sf /usr/share/zoneinfo/Europe/Stockholm /etc/localtime && hwclock --systohc
   sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen
   echo 'LANG=en_US.UTF-8' > /etc/locale.conf
   echo omarchy-vm > /etc/hostname
   mkinitcpio -P
   passwd
   grub-install --target=arm64-efi --efi-directory=/boot --bootloader-id=GRUB
   mkdir -p /boot/EFI/BOOT                                   # [+] see below
   cp /boot/EFI/GRUB/grubaa64.efi /boot/EFI/BOOT/BOOTAA64.EFI
   grub-mkconfig -o /boot/grub/grub.cfg
   useradd -m -G wheel "$VMUSER" && passwd "$VMUSER"
   id "$VMUSER"              # [+] verify NOW - see below
   EDITOR=nano visudo        # opens an editor - see "visudo" below, do not just paste on
   systemctl enable NetworkManager
   systemctl enable sshd     # [+] up on first boot, no console typing needed
   ```

   **[+] Confirm the user actually exists before moving on.** On the Mac Mini run
   `$VMUSER` was empty inside the chroot, so `useradd -m -G wheel ""` failed silently
   in the middle of a pasted block and the install completed with no user account at
   all — which does not surface until you try to SSH in after the reboot and get
   `Permission denied` (the password prompt appears even for accounts that do not
   exist, so it looks like a wrong password, not a missing user):

   ```bash
   getent passwd "$VMUSER"   # must return a line
   id "$VMUSER"              # must list wheel
   ```

   If it is missing, just create it — nothing else depends on the ordering:

   ```bash
   useradd -m -G wheel shahram
   passwd shahram
   ```

   **`visudo` opens nano and waits for you.** This is the one command in the block that
   is not fire-and-forget — the rest of step 6 does not run until you finish here. You
   are uncommenting the `wheel` line so your user can `sudo`; skip it and you have no
   `sudo` in the installed system, which every later phase depends on.

   1. `Ctrl+W`, type `wheel`, `Enter`. Cycle with `Ctrl+W`+`Enter` until you are on:

      ```
      # %wheel ALL=(ALL:ALL) ALL
      ```

      **Not** the `NOPASSWD` variant just below it — leave that one commented:

      ```
      # %wheel ALL=(ALL:ALL) NOPASSWD: ALL
      ```

   2. `Home`, then `Delete` twice to remove the `#` and the space. The line must end up
      with no leading whitespace:

      ```
      %wheel ALL=(ALL:ALL) ALL
      ```

   3. `Ctrl+O`, `Enter` to write, `Ctrl+X` to exit.

   `visudo` syntax-checks on exit. If it complains, take the re-edit option — never
   force the save, a broken `/etc/sudoers` removes `sudo` entirely. Verify:

   ```bash
   sudo -l -U "$VMUSER"                  # want a line granting (ALL : ALL) ALL
   ```

   Check it functionally, not textually. `/etc/sudoers` is mode `0440 root:root`, so
   `grep` on it as a non-root user prints `Permission denied` to stderr and nothing to
   stdout — which looks exactly like "the edit did not work" and sends you off fixing
   something that was never broken. If you do grep it, be root and use `grep -n wheel`
   without an anchor so you can see commented and uncommented lines alike.

   If nano refuses to start at all, that is the `TERM` problem — `export TERM=linux`
   at the top of this step.

   **[+] Why the extra copy:** `--bootloader-id=GRUB` writes `/EFI/GRUB/grubaa64.efi`
   and an NVRAM boot entry. Some UEFI firmware ignores the NVRAM entry and only looks
   at the removable-media fallback path `/EFI/BOOT/BOOTAA64.EFI`, which gives you a VM
   that installs cleanly and then refuses to boot. The copy costs nothing if the NVRAM
   entry works. (`grub-install --removable` does the same thing in one step.)

7. Exit the chroot and **power off** rather than reboot — you do not want to race the
   boot menu, and the ISO is easier to detach with the VM stopped.

   In the guest:

   ```bash
   exit                 # leave the chroot
   umount -R /mnt
   poweroff
   ```

   On the Mac, VM stopped:

   ```bash
   prlctl set "Omarchy 4" --device-set cdrom0 --disable
   prlctl list -i "Omarchy 4" | grep -E 'hdd0|cdrom0'   # want cdrom0 (-) and hdd0 (+)
   prlctl start "Omarchy 4"
   ```

   Same `(+)`/`(-)` flag as the disk. GUI equivalent: Configure > Hardware > CD/DVD 1,
   uncheck **Connected**; or with the VM running, Devices > CD/DVD > Disconnect. Set
   Hard Disk first in the boot order while you are in there.

   To re-attach the ISO later for a rescue boot:
   `prlctl set "Omarchy 4" --device-set cdrom0 --enable`. GRUB prints
   `efi_uga.mod not found` — harmless, press any key.

> Snapshot: `phase-1-base`

---

## Phase 2 — SSH in from the Mac immediately

Parallels Tools do not work on ARM Arch, so there is **no clipboard sharing with
macOS**. Do not type long commands into the VM console.

```bash
ip a                        # note the address
```

From the Mac: `ssh $VMUSER@<address>` (then set `VMHOST` in your Mac shell).

**Ghostty users:** the VM has no terminfo entry for it and nano etc. will refuse to
start. On the VM:

```bash
echo 'export TERM=xterm-256color' >> ~/.bashrc
```

**[+]** Copy the helper script over now, before Omarchy has a chance to break pacman:

```bash
cd /Users/shahram/source/repos/omarchy4-setup-mac-mini   # on the Mac
scp scripts/fix-pacman-arm.sh $VMUSER@$VMHOST:~/
```

---

## Phase 3 — Pacman config: fix it once, up front

This is the single biggest time sink in the original guide — the author hit it
**four separate times.** Everything Omarchy-branded assumes x86_64, and both the
official install script and Omarchy's own setup scripts overwrite your pacman config
with `stable-mirror.omarchy.org` plus `[multilib]` and `[omarchy]` repos. Neither
exists for aarch64, so afterwards every pacman command 404s.

**[+] Instead of fixing it reactively, run the helper whenever pacman 404s:**

```bash
sudo ~/fix-pacman-arm.sh
```

It restores the live config *and* overwrites Omarchy's templates under
`/usr/share/omarchy/default/pacman/` (which is what re-breaks you otherwise). Safe to
run at any point, before or after Omarchy is installed.

The correct state it writes:

- `Server = http://mirror.archlinuxarm.org/$arch/$repo` — **note the ordering.** Arch
  Linux ARM uses `$arch/$repo`, *not* x86 Arch's `$repo/$arch`. The original author
  lost time on exactly this.
- `Architecture = auto`, `SigLevel = Never`
- exactly four repos: `[core] [extra] [alarm] [aur]`, each `Include`-ing the mirrorlist
- **no** `[multilib]`, **no** `[omarchy]`

> **Do NOT run `curl https://omarchy.org/install | bash`.** Its first action is
> overwriting your mirrorlist with the x86 mirror, and it fails anyway.

> `omarchy update` restores the x86 templates. Re-run `fix-pacman-arm.sh` after
> **every** update. Forever. This does not go away.

---

## Phase 4 — Download the aarch64 bundle

Six signed packages. The channel pointer resolves to the current release tag, so this
always fetches the latest:

```bash
mkdir -p ~/omarchy-bundle && cd ~/omarchy-bundle
chan=https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-quattro-channel/asahi-quattro-channel
tag=$(curl -fsSL "$chan" | awk -F= '$1=="release_tag"{print $2}')
base=https://github.com/maralcbr/omarchy-pkgs/releases/download/$tag
curl -fsSLO "$base/asahi-quattro-bundle.manifest"
for f in $(awk -F'|' '/^package=/{print $5}' asahi-quattro-bundle.manifest); do
  curl -fSLO --retry 3 "$base/$f"
done
awk -F'|' '/^package=/{print $6 " " $5}' asahi-quattro-bundle.manifest | sha256sum -c -
```

All six checksum lines must say **OK**. Bundle contents: `omarchy-keyring`,
`omarchy-settings-dev`, `omarchy-dev`, `omarchy-nvim`, `quickshell-git`,
`ttf-jetbrains-mono-nerd-basic` — all plain aarch64 or arch-independent, no Asahi
hardware components.

**[+] Save `source_commit` from the manifest now**, you need it in Phase 8:

```bash
grep -m1 source_commit asahi-quattro-bundle.manifest | tee ~/omarchy-source-commit.txt
```

---

## Phase 5 — Dependencies, then the bundle

The runtime dependency list ships inside `omarchy-dev` itself. Extract it, drop the
Asahi hardware entries (no bare-metal kernel/firmware in a VM) and the three the
bundle already provides:

```bash
cd ~/omarchy-bundle
bsdtar -xOf omarchy-dev-*.pkg.tar.xz usr/share/omarchy/install/omarchy-base-asahi.packages > all.packages
grep -vE '^\s*(#|$)' all.packages | tr -s ' \n' '\n' \
  | grep -vxE 'asahi-desktop-meta|asahi-fwextract|linux-asahi|linux-asahi-headers|widevine' \
  | grep -vxE 'omarchy-nvim|quickshell-git|ttf-jetbrains-mono-nerd-basic' | sort -u > repo.packages
```

Check what the ALARM repos actually have **before** installing anything:

```bash
sudo pacman -Sy >/dev/null 2>&1 && echo "pacman OK" || echo "pacman BROKEN - run fix-pacman-arm.sh"
for p in $(cat repo.packages); do pacman -Si "$p" &>/dev/null || echo "MISSING: $p"; done | tee missing.txt
```

Check pacman first: if Omarchy has already broken it, **every** package reports as
missing and the list is worthless. Everything-missing is the signature of a broken
pacman config, not of genuinely absent packages. The `tee` keeps the list for Phase 8.
The loop is read-only and idempotent — safe to re-run at any point, and the answer does
not change once the bundle is installed, since it queries the repos rather than what is
installed.

**Confirmed identical on this run (4.0.1-mac.1): the same 10 packages**, the ones the
official installer builds from source. Still trust your own output over this list — but
two independent runs on different releases agreeing is a good sign it is stable:

`aether` `cliamp` `localsend` `mise` `python-terminaltexteffects` `ttf-ia-writer`
`ufw-docker` `xdg-terminal-exec` `yaru-icon-theme` `yay`

```bash
grep -vxE 'aether|cliamp|localsend|mise|python-terminaltexteffects|ttf-ia-writer|ufw-docker|xdg-terminal-exec|yaru-icon-theme|yay' \
  repo.packages > repo.final
sudo pacman -Syu --needed --noconfirm $(cat repo.final)
sudo pacman -U --needed *.pkg.tar.xz
cat /usr/share/omarchy/version        # 4.0.x-mac.* - got 4.0.1-mac.1 on this run
```

> Snapshot: `phase-5-omarchy-installed`

---

## Phase 6 — System and user setup, hardware checks removed

Two non-obvious things about Omarchy's setup commands:

1. They print almost nothing. **Real output goes to `/var/log/omarchy-install.log`.**
2. They run a series of small scripts and **stop dead at the first failure** — everything
   after the failing script silently does not run.

The original loop is: run setup → read log → find `Failed:` → disable that script →
re-run. Repeat until the log ends with `Omarchy Setup Completed`.

**[+] Pre-disable the three scripts already known to fail in a VM**, so you (hopefully)
run the loop once instead of four times:

```bash
for s in config/snapper.sh config/firewall.sh user/mise-work.sh; do
  sudo sh -c "printf '#!/bin/bash\nexit 0\n' > /usr/share/omarchy/install/$s"
done
```

Why each one fails:

- `config/snapper.sh` — configures btrfs snapshots; our disk is ext4 and snapper is absent.
- `config/firewall.sh` — fails on the missing `ufw-docker` package.
- `user/mise-work.sh` — needs `mise` (not installed until Phase 8) and downloads **x86**
  Node.js archives.

**[+] Firewall: do it by hand, and open SSH.** The original author replaced the script
with the plain ufw rules and added `ufw allow 22/tcp` — **without that rule the firewall
locks you out of SSH after reboot**, which on a VM with no clipboard is genuinely painful:

```bash
sudo pacman -S --needed ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp                 # do not skip this
sudo sed -i 's/^ENABLED=.*/ENABLED=yes/' /etc/ufw/ufw.conf
sudo systemctl enable ufw
```

**[+] Enable periodic TRIM** so the Parallels expanding disk can actually shrink. The
`discard` mount option is the wrong way — it trims inline on every delete and costs
performance. Use the timer:

```bash
sudo systemctl enable --now fstrim.timer
systemctl status fstrim.timer      # runs weekly
```

Then run setup — system as root, user as yourself:

```bash
sudo omarchy-apply-system --install-user "$VMUSER" --first-install
OMARCHY_SETUP_CONTEXT=fresh-install omarchy-provision-user --force --first-install
```

After each run: `sudo grep -n 'Failed:' /var/log/omarchy-install.log`. If anything is
listed, blank that script the same way and re-run.

User setup is done when `~/.local/state/omarchy/done/finalize-user` exists.

> Snapshot: `phase-6-setup-complete`

---

## Phase 7 — First login: two guaranteed problems

**Problem 1 — login always fails.** Password is correct but the journal shows
`Authentication for user "" failed`. The Omarchy login theme expects the username to be
pre-seeded by their ISO installer, which we never used, so it submits an empty username.
Fix is autologin, which is how stock Omarchy behaves anyway:

```bash
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/50-autologin.conf <<EOF
[Autologin]
User=$VMUSER
Session=omarchy
EOF
sudo systemctl restart sddm
```

> Note: combined with no disk encryption, the VM now boots straight to a desktop with
> no authentication at all. Fine for a disposable experiment; do not put real
> credentials in it.

**Problem 2 — plain Hyprland loads instead of Omarchy** (yellow autogenerated-config
warning bar, Hyprland welcome window). Omarchy ships user config through `/etc/skel`,
which only applies to users created *after* the packages were installed — ours is older.

```bash
omarchy-reinstall-configs        # limine/bootloader errors are expected, we use GRUB
ls -d ~/.config/omarchy          # must exist now
sudo systemctl restart sddm
```

**Resolution / fullscreen.** The VM boots at 1024x768 and there is no dynamic resizing
without Parallels Tools, so the guest resolution is fixed at boot by a kernel parameter:

```bash
sudo sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"/&video=Virtual-1:$VMRES /" /etc/default/grub
grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub    # eyeball it before regenerating
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot
```

After reboot, check what you actually got — the virtual GPU may not honour the request:

```bash
hyprctl monitors        # or: cat /sys/class/drm/*/modes | head
```

Three caveats for a 5120x1440 ultrawide:

- **The `@120` is probably ignored.** Parallels' virtual display is not a real panel;
  it typically presents 60Hz regardless of what you ask for. Harmless — the mode still
  applies at 60. If `hyprctl monitors` reports 60, that is expected, not a failure.
- **Fullscreen is a host-side setting.** Parallels' View > Full Screen scales whatever
  the guest is rendering. If the guest mode does not match the display's aspect ratio
  you get letterboxing, so the guest `video=` value should match the panel exactly.
- **If the mode is rejected**, the guest falls back to 1024x768 and you see it
  immediately. Step down and retry: `3840x1080@60`, then `2560x1080@60`. Ultrawide modes
  on a virtual framebuffer are the least-tested path here.

---

## Phase 8 — Build the 10 missing packages

Without these the desktop starts but keybindings fire "command not found" notifications.
**`xdg-terminal-exec` is the critical one — the terminal will not open without it.**

```bash
git clone https://github.com/maralcbr/omarchy-pkgs.git ~/omarchy-pkgs
cd ~/omarchy-pkgs && git checkout "$(cut -d= -f2 ~/omarchy-source-commit.txt)"
cd pkgbuilds
for p in xdg-terminal-exec python-terminaltexteffects ttf-ia-writer ufw-docker localsend-bin aether cliamp; do
  (cd "$p" && makepkg -si --noconfirm) || echo "FAILED: $p"
done
```

**[+]** `xdg-terminal-exec` moved to the front of the list — build it first, verify the
terminal opens, and the rest is comfortable rather than blind.

Two packages need special handling:

- **`yay`** — build `yay-bin` from the AUR instead, it ships prebuilt aarch64 binaries.
  Then use it for `mise`, which is not in the pinned pkgbuilds:
  ```bash
  git clone https://aur.archlinux.org/yay-bin.git ~/yay-bin && (cd ~/yay-bin && makepkg -si --noconfirm)
  yay -S --noconfirm mise
  ```
- **`yaru-icon-theme`** — split package; the `yaru-gtk-theme` half depends on
  `gtk-engine-murrine`, absent from ALARM, so a group install fails. Only the icons are
  needed, and two of its files collide with `omarchy-dev`:
  ```bash
  cd ~/omarchy-pkgs/pkgbuilds/yaru-icon-theme && makepkg -f
  sudo pacman -U --overwrite '*' yaru-icon-theme-*.pkg.tar.*
  ```

> Snapshot: `phase-8-complete`

---

## Permanent limitations — accept these before starting

- `omarchy update` restores the x86 pacman templates. Re-run `fix-pacman-arm.sh` every time.
- **No Parallels Tools on ARM Arch:** no clipboard sync with macOS, no dynamic
  resolution, single display only. SSH for text, the GRUB `video=` parameter for resolution.
- x86-only apps in Omarchy's catalog (Spotify, 1Password, and similar) cannot be installed.
- Package signature verification is off (`SigLevel = Never`) and there is no disk
  encryption. This VM is not a place for real credentials.
- Unsupported by both upstreams. If it breaks, you own it.

## Open questions / to verify on this machine

- [x] Missing-package list confirmed identical to the guide's 10 on 4.0.1-mac.1.
- [x] Version drift: guide was 4.0.0-mac.6, this run got **4.0.1-mac.1** — same
      version the user installed on the M1 Pro MacBook. Nothing in the guide has
      needed adjusting for it so far.
