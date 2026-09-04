# Running `omarchy update` on Arch Linux ARM in Parallels

How to update this VM without breaking it, and why the usual breakage happens at all.

Companion to [the install checklist](2026-09-03-omarchy4-parallels-checklist.md).

---

## The root cause: failed hardware detection

Everything that goes wrong on update traces back to one script:

```bash
# /usr/bin/omarchy-hw-apple-silicon
proc_root="${OMARCHY_PROC_ROOT:-/proc}"
[[ $(uname -m) == "aarch64" ]] &&
  grep -aq 'apple,' "$proc_root/device-tree/compatible" 2>/dev/null
```

**Parallels exposes no device tree at all** — `/proc/device-tree/compatible` does not
exist in the guest — so this returns non-zero and Omarchy concludes it is running on an
ordinary x86 desktop. On a real Mac (bare metal Asahi) it returns 0.

That single result gates the ARM behaviour across the whole system:

```
/usr/bin/omarchy-refresh-pacman
/usr/bin/omarchy-update-system-pkgs
/usr/bin/omarchy-update-asahi-bundle
/usr/bin/omarchy-update-keyring
/usr/bin/omarchy-update-aur-pkgs
/usr/bin/omarchy-migrate
/usr/share/omarchy/install/hardware/pacman.sh
/usr/share/omarchy/install/post-install/pacman.sh
...and ~10 more
```

Most importantly, `omarchy-refresh-pacman` **already refuses to damage an ARM system**:

```bash
if omarchy-hw-apple-silicon; then
  echo "Error: Omarchy package channels are not available for Apple Silicon; \
preserving the existing Arch Linux ARM repositories" >&2
  exit 1
fi
```

So the pacman config was never being overwritten because ARM is unsupported. It was
overwritten because Omarchy could not tell it was on ARM. **This is a detection bug in a
VM, not an incompatibility.**

## The fix: a detection shim

`OMARCHY_PROC_ROOT` works but is fragile — many of these scripts are `requires-sudo`,
and `sudo` strips the environment. A shim in `/usr/local/bin` survives that, because
that directory precedes `/usr/bin` both in a normal `PATH` and in sudo's `secure_path`
(`/usr/local/sbin:/usr/local/bin:/usr/bin` on Arch).

```bash
sudo tee /usr/local/bin/omarchy-hw-apple-silicon >/dev/null <<'EOF'
#!/bin/bash
# Shim: Parallels exposes no device tree, so the stock check cannot detect Apple
# Silicon in a VM. This host IS Apple Silicon (arm64 guest on an M4 Pro), so report
# true and let Omarchy take its ARM paths. Remove this file for stock behaviour.
[[ $(uname -m) == "aarch64" ]]
EOF
sudo chmod +x /usr/local/bin/omarchy-hw-apple-silicon

omarchy-hw-apple-silicon;      echo "user exit: $?"    # want 0
sudo omarchy-hw-apple-silicon; echo "sudo exit: $?"    # want 0
```

Both must be `0`. The `aarch64` guard means it cannot claim ARM on the wrong machine.

**Undo:** `sudo rm /usr/local/bin/omarchy-hw-apple-silicon`

### What this changes about `fix-pacman-arm.sh`

`scripts/fix-pacman-arm.sh` writes exactly four repos and strips `[omarchy]`. That was
correct for a system whose detection was broken. With the shim in place it is **partly
wrong**: `install/hardware/pacman.sh` deliberately adds an `[omarchy]` repo pointing at
the *aarch64* release server, with a verified GPG key —

```
[omarchy]
SigLevel = Required DatabaseOptional
Server = https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-packages-<tag>
```

— which is legitimate and wanted. Running the fix script after a successful shimmed
update would delete it. **With the shim working, treat `fix-pacman-arm.sh` as a recovery
tool for when detection is broken, not as routine post-update hygiene.**

### Residual risk

The Asahi hardware scripts (`install/hardware/apple/fix-brcmfmac-supplicant.sh`,
`fix-asahi-hid-race.sh`) are gated on the same detection and will now believe they
apply. They target Broadcom WiFi firmware and an Asahi HID race, neither of which exists
in a VM, so they should no-op or fail harmlessly — but that is reasoning, not evidence.
Watch for them in the update log.

`omarchy-setup-direct-boot` is also gated on the detection and *is* bootloader territory,
but it is reachable only from the Omarchy menu (`omarchy-menu.jsonc`), never from the
update path. Do not run it in a VM.

---

## The checklist

### 1. Pre-flight

```bash
# Mac - the safety net. Do not skip.
prlctl snapshot "Omarchy 4" --name "pre-update-$(date +%Y%m%d)"
prlctl snapshot-list "Omarchy 4"
```

```bash
# VM - record the starting state so any change is attributable
cat /usr/share/omarchy/version
cat /var/lib/omarchy/asahi-quattro-release 2>/dev/null
pacman -Q | wc -l
grep -c efi_uga /boot/grub/grub.cfg          # 0 if the GRUB patch is in place
sudo pacman -Sy                              # must be clean before starting
omarchy-hw-apple-silicon; echo "exit: $?"    # must be 0 - the shim is the whole point
```

If `pacman -Sy` is *not* clean before you start, fix that first
(`sudo ~/fix-pacman-arm.sh`) — otherwise you cannot tell what the update broke.

### 2. Run it

```bash
omarchy update
```

Not under `sudo` — it escalates internally, and running the whole thing as root changes
which user the user-level steps target.

It logs to `/tmp/omarchy-update.log` via `script`, so the full transcript survives even
if the terminal dies.

**Expected, harmless:**

- `Continuing the update without a snapshot.` — Snapper is deliberately absent (we
  blanked `snapper.sh`; the disk is ext4). Exit 127 is handled and ignored by design.
- Apple Silicon bundle steps running at all — that is the shim working.

**Abort and snapshot-restore if you see:**

- `stable-mirror.omarchy.org` anywhere — detection failed and the x86 path is running
- x86 package downloads, or `[multilib]` reappearing
- anything touching the bootloader or `m1n1`

### 3. Post-update checks

```bash
cat /usr/share/omarchy/version                       # did it move?
grep -nE '^\[|^Server' /etc/pacman.conf              # repos: core/extra/alarm/aur + [omarchy] on the asahi server
sudo pacman -Sy                                      # must be clean
grep -c efi_uga /boot/grub/grub.cfg                  # 0; if not, grub was updated
head -2 /usr/share/omarchy/install/config/snapper.sh # still the exit-0 stub?
```

The last one matters: if the update restored `/usr/share/omarchy/install/`, the three
scripts blanked in install Phase 6 are back and will fail on the next setup run. Re-blank
whichever returned:

```bash
for s in config/snapper.sh config/firewall.sh user/mise-work.sh; do
  printf '#!/bin/bash\nexit 0\n' | sudo tee "/usr/share/omarchy/install/$s" >/dev/null
done
```

If `grep -c efi_uga` is non-zero, GRUB was updated: `sudo ~/fix-grub-efi-uga.sh`.

### 4. Reboot and verify

```bash
sudo reboot
```

Then, in order — each failure points somewhere different:

| Check | Failure means |
|---|---|
| Boots with no keypress pause | GRUB was updated → `fix-grub-efi-uga.sh` |
| SSH still works | `ufw` rules were reset → `sudo ufw allow 22/tcp` |
| Desktop reaches Omarchy, not bare Hyprland | user configs were replaced → `omarchy-reinstall-configs` |
| Terminal opens from its keybinding | one of the ten source-built packages went missing |
| Resolution still 5120x1440 | `monitors.lua` was overwritten → re-add the `hl.monitor()` line |

### 5. Rollback

Repair rather than roll back when the damage is one of the known, understood items
above. **Restore the snapshot** when the system will not boot, the desktop will not
start, or `pacman` is in a state you cannot explain — an unexplained pacman config on a
system with `SigLevel` involved is not worth debugging on a disposable VM.

```bash
# Mac
prlctl snapshot-list "Omarchy 4"
prlctl snapshot-switch "Omarchy 4" --id <snapshot-id>
```

---

## Findings log

Record what each update actually did, so the guesswork above turns into fact.

### Update 1 — (pending)

- Date:
- Version before → after:
- Shim in place: yes
- Pacman config survived:
- `install/` scripts restored:
- GRUB updated:
- Anything unexpected:
