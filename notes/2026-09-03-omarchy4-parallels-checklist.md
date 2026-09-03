# Omarchy 4 (Quattro) on Mac Mini M4 Pro / Parallels — working checklist

Date: 2026-09-03
Target: Omarchy 4.0.0-mac.* on Arch Linux ARM (aarch64) in Parallels Desktop
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

Parallels: new VM from the ISO, type **Other Linux**. 4 CPUs / 16 GB RAM / 64 GB disk
worked for the original author; on an M4 Pro you can be more generous.

### Disk controller: choose SATA, not IDE

**Set the hard disk to SATA before first boot.** If Parallels offers IDE at all on
Apple Silicon, do not pick it.

Reasoning: IDE/PATA emulation is a legacy x86 PC-chipset device. Its Linux drivers
(`ata_piix` and friends) are x86 config options and are generally **not built into
aarch64 kernels**, including Arch Linux ARM's. AHCI/SATA is architecture-neutral and is
compiled in. So on an ARM guest an IDE disk can be present in the VM and still have no
driver — the disk simply does not appear, which is exactly the "installer cannot see my
hard drive" failure. SATA also gives you `/dev/sda`, which is what every command in this
checklist assumes.

### If the disk still does not show up

Run these in the archboot shell **before** partitioning:

```bash
lsblk                      # expect sda, ~64G
ls /dev/sd* /dev/vd* /dev/nvme* 2>/dev/null
dmesg | grep -iE 'ahci|ata[0-9]|sd [0-9]|nvme'   # look for the controller binding
```

Interpretation:

- `sda` present → good, proceed.
- **Nothing at all** → almost certainly the IDE/PATA situation above. Shut the VM down,
  switch the disk to SATA in Parallels, reboot the ISO. Do not try to fix this from
  inside the guest.
- `nvme0n1` instead → the disk is on NVMe. Everything works, but **substitute
  `/dev/nvme0n1` for `/dev/sda`, and `p1`/`p2`/`p3` for the partition suffixes**
  (`/dev/nvme0n1p1`, not `/dev/nvme0n11`) in every command below.
- `vda` → virtio. Same deal, substitute `/dev/vda` / `vda1`.
- `sda` present but `cfdisk` refuses to write → the ISO is still holding it, or the
  disk is under 1M. Re-check `lsblk` size.

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
   sed -i 's/^\s*SigLevel.*/SigLevel = Never/' /etc/pacman.conf   # again, new system
   ln -sf /usr/share/zoneinfo/Europe/Stockholm /etc/localtime && hwclock --systohc
   sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen
   echo 'LANG=en_US.UTF-8' > /etc/locale.conf
   echo omarchy-vm > /etc/hostname
   mkinitcpio -P
   passwd
   grub-install --target=arm64-efi --efi-directory=/boot --bootloader-id=GRUB
   grub-mkconfig -o /boot/grub/grub.cfg
   useradd -m -G wheel "$VMUSER" && passwd "$VMUSER"
   EDITOR=nano visudo        # uncomment: %wheel ALL=(ALL:ALL) ALL
   systemctl enable NetworkManager
   systemctl enable sshd     # [+] up on first boot, no console typing needed
   ```

7. Exit chroot, reboot, **disconnect the ISO in Parallels**. GRUB prints
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
for p in $(cat repo.packages); do pacman -Si "$p" &>/dev/null || echo "MISSING: $p"; done
```

The original author got exactly 10 missing — the ones the official installer builds
from source. Expect the same list, but **trust your own output over this one**, it can
drift:

`aether` `cliamp` `localsend` `mise` `python-terminaltexteffects` `ttf-ia-writer`
`ufw-docker` `xdg-terminal-exec` `yaru-icon-theme` `yay`

```bash
grep -vxE 'aether|cliamp|localsend|mise|python-terminaltexteffects|ttf-ia-writer|ufw-docker|xdg-terminal-exec|yaru-icon-theme|yay' \
  repo.packages > repo.final
sudo pacman -Syu --needed --noconfirm $(cat repo.final)
sudo pacman -U --needed *.pkg.tar.xz
cat /usr/share/omarchy/version        # must print 4.0.0-mac.*
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

- [ ] Confirm the missing-package list matches the 10 above (Phase 5 check loop).
- [ ] The source guide is one person's log on an M2 Max, ~2026-08-18, pinned to
      4.0.0-mac.6. Check `/usr/share/omarchy/version` against what the bundle actually
      delivers and note any drift here.
