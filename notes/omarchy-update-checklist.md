# Running `omarchy update` on Arch Linux ARM in Parallels

How to update this VM without breaking it.

Companion to [the install checklist](2026-09-03-omarchy4-parallels-checklist.md) and
[the detection note](2026-09-05-apple-silicon-detection.md).

**Status: `omarchy update` works on this VM as-is.** It completed cleanly on 2026-09-04
with hardware detection still failing and no workarounds applied. See the Findings log.

---

## What we expected to be wrong, and wasn't

Two assumptions carried from the install phase turned out not to hold for
`omarchy-dev 4.0.0.r6673.g5939caf-1`. Both were reasoning, not measurement, and both are
now measured.

### `omarchy update` does not rewrite pacman config

The install notes say the x86 pacman templates come back after every update, forever.
They did not. `/etc/pacman.d/mirrorlist` has not been modified since install day, and
`/etc/pacman.conf` was only touched by our own `sed`.

The reason is structural, not luck. `omarchy-refresh-pacman` is the only script that
rewrites pacman config, and **nothing in the update path calls it**:

```bash
grep -n 'refresh-pacman' /usr/bin/omarchy-update /usr/bin/omarchy-update-*   # no matches
```

It is reachable from the Omarchy menu and from `install/`, which is why it bit us during
install. It is not part of `omarchy update`.

**So `fix-pacman-arm.sh` is not routine post-update hygiene.** It is a recovery tool.
Run it when pacman is actually broken, not on a schedule.

### Hardware detection is not required for an update to succeed

Detection still fails here — Parallels exposes no device tree, so
`omarchy-hw-apple-silicon` returns 2. The update path therefore skips its ARM branch. It
completed anyway, because on this VM the ARM branch's main effect is a no-op.

That branch adds `--ignore` for six packages in `omarchy-update-system-pkgs` and
`omarchy-update-aur-pkgs`. All six are **foreign** packages — installed from the
downloaded bundle, present in no configured repo:

```bash
pacman -Qm | grep -E 'omarchy|quickshell|jetbrains'
#   omarchy-dev  omarchy-keyring  omarchy-nvim
#   omarchy-settings-dev  quickshell-git  ttf-jetbrains-mono-nerd-basic
grep -c '^\[omarchy\]' /etc/pacman.conf   # 0
yay -Si omarchy-dev                       # -> No AUR package found for omarchy-dev
```

`pacman -Syu` cannot upgrade a package that exists in no repo, and `yay -Sua` cannot
upgrade one that is not in the AUR. **Nothing can overwrite the aarch64 bundle packages,
so there is nothing for `--ignore` to protect.** That was the "whole ballgame" claim in
the old handoff note; it was wrong.

The one thing detection genuinely gates is the signed bundle step — new *Omarchy*
versions. Without it, the bundle packages stay frozen at whatever was installed. See
[the detection note](2026-09-05-apple-silicon-detection.md) for why turning it on right
now would make updates **less** reliable, not more.

## What actually went wrong instead

Not Omarchy. Arch Linux ARM shipped an internally inconsistent `[extra]`:

```
:: unable to satisfy dependency 'libaquamarine.so=13-64' required by hyprtoolkit
:: installing aquamarine (0.15.0-2) breaks dependency 'libaquamarine.so=13-64' required by hyprland
error: failed to prepare transaction (could not satisfy dependencies)
```

`aquamarine 0.15.0-2` bumped its soname to `libaquamarine.so=14`, but ALARM had not yet
rebuilt `hyprland` or `hyprtoolkit`, which still require `so=13`. Nothing in any repo
requires `so=14`, so the new aquamarine is currently uninstallable on ALARM. This would
hit any Omarchy ARM machine, VM or not.

Omarchy's `omarchy-update-system-pkgs-when-conflicted` only recovers from
`unresolvable package conflicts detected` and `exists in filesystem`. A dependency
*resolution* failure is neither, so it correctly refused to guess and aborted the whole
update. Nothing was installed — it failed at transaction preparation.

**Fix — hold the offending package.** `omarchy update` exposes no `--ignore`, so it goes
in the config:

```bash
sudo sed -i '/^LocalFileSigLevel/a IgnorePkg         = aquamarine' /etc/pacman.conf
```

This is temporary and must be removed once ALARM catches up, or the compositor stack
silently rots. Check periodically:

```bash
sudo pacman -Sy                           # NOT optional - see below
pacman -Si hyprland | grep aquamarine     # when this says so=14, drop the hold
sudo sed -i '/^IgnorePkg.*aquamarine/d' /etc/pacman.conf
```

**`pacman -Si` reads the local sync DB, which can be days old.** On 2026-09-05 it was
answering from a snapshot taken before the update and would have given the right answer
by luck rather than by being current. Sync first, or read the live repo directly — which
needs no sudo and cannot be stale:

```bash
curl -fsSL -o /tmp/extra.db http://mirror.archlinuxarm.org/aarch64/extra/extra.db
mkdir -p /tmp/edb && tar -xzf /tmp/extra.db -C /tmp/edb
grep -rl 'libaquamarine.so=13-64' /tmp/edb/*/depends | xargs -r -n1 dirname | xargs -r -n1 basename
```

Deps live in each package's `depends` file, not `desc`. An empty result means nothing in
`[extra]` still wants `so=13` and the hold can go.

`fix-pacman-arm.sh` carries the same hold, because it rewrites `pacman.conf` wholesale
and would otherwise silently drop it. Remove it from both places at the same time.

> **General rule.** A dependency failure naming two packages from `[extra]` is an
> upstream ALARM lag, not an Omarchy problem. Confirm with
> `pacman -Su --print --ignore <pkg>`; if that resolves cleanly, hold `<pkg>` and move on.

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
pacman -Q omarchy-dev
pacman -Q | wc -l
grep -c efi_uga /boot/grub/grub.cfg          # 0 if the GRUB patch is in place
sudo pacman -Sy                              # must be clean before starting
```

If `pacman -Sy` is *not* clean before you start, fix that first
(`sudo ~/fix-pacman-arm.sh`) — otherwise you cannot tell what the update broke.

Detection is **not** a pre-flight requirement. `omarchy-hw-apple-silicon` returning
non-zero is the normal, working state of this VM.

### 2. Run it

```bash
omarchy update
```

Not under `sudo` — it escalates internally, and running the whole thing as root changes
which user the user-level steps target.

It logs to `/tmp/omarchy-update.log` via `script`. **Copy that log somewhere before
rebooting** — `/tmp` is cleared on boot and the transcript is gone.

**Expected, harmless:**

- `Continuing the update without a snapshot.` — Snapper is deliberately absent (we
  blanked `snapper.sh`; the disk is ext4). Exit 127 is handled and ignored by design.
- No Apple Silicon bundle line. Detection is off; the step is skipped.
- `omarchy-update-keyring` installing `archlinux-keyring` rather than
  `archlinuxarm-keyring`. That is the x86 branch, and it is harmless — the package
  exists for aarch64 and installs cleanly.
- A dependency-resolution abort. See "What actually went wrong instead" above.

**Abort and snapshot-restore if you see:**

- `stable-mirror.omarchy.org` anywhere, or `[multilib]` reappearing
- x86 package downloads
- anything touching the bootloader or `m1n1`

### 3. Post-update checks

```bash
pacman -Q omarchy-dev                                # did it move?
grep -nE '^\[|^Server|^IgnorePkg' /etc/pacman.conf   # core/extra/alarm/aur, no [omarchy], hold intact
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
system with `SigLevel = Never` is not worth debugging on a disposable VM.

```bash
# Mac
prlctl snapshot-list "Omarchy 4"
prlctl snapshot-switch "Omarchy 4" --id <snapshot-id>
```

---

## Findings log

Record what each update actually did, so the guesswork above turns into fact.

### Update 1 — 2026-09-04 / 2026-09-05 — succeeded

- **Version before → after:** `omarchy-dev 4.0.0.r6673.g5939caf-1` → unchanged. The
  bundle step is what moves this, and it was skipped. System packages moved; Omarchy
  itself did not.
- **Detection enabled:** no. `omarchy-hw-apple-silicon` → exit 2 throughout.
  `enable-arm-detection.sh` was never run.
- **Attempt 1:** aborted at transaction preparation on the `libaquamarine.so=13-64`
  dependency failure. Nothing installed, nothing changed.
- **Attempt 2:** after `IgnorePkg = aquamarine`, completed. 33 packages upgraded
  (mesa `1:26.2.1`→`1:26.2.2`, chromium `…64`→`…75`, hyprtoolkit `0.5.4-4`→`0.5.4-5`,
  util-linux, foot, wireplumber, nftables, …), 4 AUR packages via `yay`
  (aether, cliamp, localsend-bin, xdg-terminal-exec), then 13 orphaned build deps pruned
  (`go`, `bats`, `scdoc`, `gtk-layer-shell`, the python build chain).
- **Pacman config survived:** yes. `mirrorlist` untouched since install; `pacman.conf`
  modified only by our own `sed`. No `[multilib]`, no `[omarchy]`, no
  `stable-mirror.omarchy.org` at any point.
- **`install/` scripts restored:** no. All three stubs still `exit 0`.
- **GRUB updated:** no. `grub.cfg` untouched since install; `efi_uga` count still 0.
- **Migrations:** 94 of 94 applied, 0 pending.
- **Anything unexpected:** yes, two things, both now written up above — the update path
  never touches pacman config, and the ARM `--ignore` list is a no-op on this VM.
- **Left behind:** `IgnorePkg = aquamarine`, to remove when ALARM rebuilds `hyprland`
  and `hyprtoolkit` against `libaquamarine.so=14`.

---

## Hold watch — `aquamarine`

Checked against the live ALARM `[extra]` database, not the local sync DB.

| Checked | `aquamarine` | `hyprland` | `hyprtoolkit` | Hold |
|---|---|---|---|---|
| 2026-09-05 | 0.15.0-2, provides `so=14` (built 09-04) | 0.56.1-3, needs `so=13` (built 08-01) | 0.5.4-5, needs `so=13` (built 09-04) | **stays** |

2026-09-05 note: `hyprtoolkit` was rebuilt on 09-04, *after* aquamarine 0.15 landed, and
still came out linked against `so=13` — so ALARM's builder still had aquamarine 0.14 in
its chroot. The rebuild has not started, rather than being queued and imminent. No point
re-checking daily.
