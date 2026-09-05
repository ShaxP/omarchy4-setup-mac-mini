# Apple Silicon detection in a Parallels guest

Why Omarchy thinks this VM is an x86 desktop, what that actually costs, and why the fix
is written but deliberately **not applied**.

Verified 2026-09-05 against `omarchy-dev 4.0.0.r6673.g5939caf-1`.

## The short version

Omarchy's ARM behaviour is gated on `omarchy-hw-apple-silicon`, which reads the device
tree. Parallels exposes none, so it returns non-zero and every ARM branch is skipped.

**This does not stop `omarchy update` from working** — that was measured on 2026-09-04,
and the update completed with detection still failing. See the Findings log in
[the update checklist](omarchy-update-checklist.md).

What it does cost: the signed bundle step never runs, so the six aarch64 bundle packages
stay frozen at whatever the install put there. That is the only real consequence.

## The mechanism

```bash
# /usr/bin/omarchy-hw-apple-silicon
proc_root="${OMARCHY_PROC_ROOT:-/proc}"
[[ $(uname -m) == "aarch64" ]] &&
  grep -aq 'apple,' "$proc_root/device-tree/compatible" 2>/dev/null
```

`/proc/device-tree/` does not exist in the guest. On bare-metal Asahi it does.

`omarchy-update-asahi-bundle` performs a **second, independent** check that ignores
`OMARCHY_PROC_ROOT` and uses its own prefix variable:

```bash
root_path() { printf '%s%s\n' "${OMARCHY_ASAHI_ROOT:-}" "$1"; }
compatible=$(tr '\0' '\n' <"$(root_path /proc/device-tree/compatible)" 2>/dev/null || true)
```

`OMARCHY_ASAHI_ROOT` is a whole-system prefix, not a `/proc` knob — it is also applied to
`/boot/vmlinuz-linux-asahi`, `/boot/grub/grub.cfg`, `/etc/pacman.conf` and
`/etc/NetworkManager`. So the two variables need different values off one tree:
`OMARCHY_PROC_ROOT` appends `/device-tree/compatible`, `OMARCHY_ASAHI_ROOT` appends
`/proc/device-tree/compatible`.

## Correction: the PATH shim never worked

An earlier session installed `/usr/local/bin/omarchy-hw-apple-silicon` as a shim. It
cannot work, for two independent reasons:

1. `/usr/share/omarchy/bin` **precedes** `/usr/local/bin` in `PATH`, and
   `/usr/share/omarchy/bin/omarchy-hw-apple-silicon` is a symlink to the stock `/usr/bin`
   copy. The shim was shadowed. Measured in a normal login shell:

   ```
   /usr/local/bin/omarchy-hw-apple-silicon           exit=0
   /usr/bin/omarchy-hw-apple-silicon                 exit=2
   /usr/share/omarchy/bin/omarchy-hw-apple-silicon   exit=2   <-- the one PATH picks
   ```

2. `omarchy-migrate` does not consult `PATH` at all — it calls
   `$OMARCHY_PATH/bin/omarchy-hw-apple-silicon` by absolute path.

The stock detector already honours `OMARCHY_PROC_ROOT`, which reaches every caller
including the absolute-path one and survives package updates. That is the mechanism
`enable-arm-detection.sh` uses. **The shim is still on disk at
`/usr/local/bin/omarchy-hw-apple-silicon` and is inert** — harmless, but delete it if you
are tidying.

## Correction: the `--ignore` list is not the point

The previous version of this note claimed the ARM branch's `pacman -Syu --ignore` of the
six bundle packages was "the whole ballgame" — the thing standing between us and a
working update. That was wrong, and it was wrong by reasoning rather than measurement.

All six are foreign packages in no configured repo, and `omarchy-dev` is not in the AUR.
Neither `pacman -Syu` nor `yay -Sua` has any upgrade candidate for them. There is nothing
for `--ignore` to protect against. Full working in
[the update checklist](omarchy-update-checklist.md).

## Why satisfying the device tree is not enough

Past its device-tree check, `omarchy-update-asahi-bundle` gates on things this VM
structurally cannot have:

| Gate | Status | Fakeable? |
| --- | --- | --- |
| `$ROOT/boot/vmlinuz-linux-asahi` exists | VM has `/boot/Image` (linux-aarch64) | via `OMARCHY_ASAHI_ROOT` |
| `pacman -Qq linux-asahi` | **not installed** | **no** — not `root_path`'d, hits the real pacman DB |
| `[asahi-alarm]` in pacman.conf | missing | via `OMARCHY_ASAHI_ROOT` |
| NetworkManager `wifi.backend=iwd` | not set (VM has no wifi) | via `OMARCHY_ASAHI_ROOT` |

`linux-asahi` is the bare-metal Apple Silicon kernel. Installing it to satisfy a string
comparison would be wrong and probably unbootable. **Do not.**

Confirmed by sandbox test — fake roots in place, no state file:

```
Apple Silicon bundle update: /boot/vmlinuz-linux-asahi is missing
exit=2
```

## The way through, if you ever need it

The script never reaches those gates while the bundle is current. The signed channel at
`maralcbr/omarchy-pkgs/releases/download/asahi-quattro-channel` says:

```
sequence=21
release_tag=asahi-quattro-5939caf7
source_commit=5939caf720c1fb7e137d57ab87c0182f2132e5a3
```

and the installed packages provide exactly that commit:

```
omarchy-settings-dev  Provides: omarchy-quattro-bundle=5939caf720c1fb7e137d57ab87c0182f2132e5a3
omarchy-dev           Provides: omarchy-quattro-bundle=5939caf720c1fb7e137d57ab87c0182f2132e5a3
```

This VM is on the current bundle; it just has no state file saying so, because the state
file is normally written by an install this VM never performed. Writing
`/var/lib/omarchy/asahi-quattro-release` with those values makes the script take its
"up to date" branch and `exit 0` **before** any impossible hardware gate. That is a true
record, not a forgery.

Sandbox-verified against the real script with a temp state file:

```
### check mode                 exit=1  (correctly: no update available)
### update mode                Apple Silicon Quattro bundle is up to date
                               exit=0
```

## Why it is not applied

`scripts/enable-arm-detection.sh` does all of the above, as root, idempotently:

1. Creates `/var/lib/omarchy/vm-root/proc/device-tree/compatible` = `apple,parallels-vm`
2. Adds `OMARCHY_PROC_ROOT` and `OMARCHY_ASAHI_ROOT` to `/etc/environment` (pam_env, so
   every login session gets them — you must log out and back in)
3. Writes the release state file — **refusing** if the installed bundle source does not
   match, so it can never record a release the VM is not on
4. Removes the superseded PATH shim and the old `/var/lib/omarchy/vm-proc`

It has never been run, and running it today would make things **worse**:

- The update already works without it, and it protects against nothing (see above).
- It switches on `omarchy-update-asahi-bundle`, which exits 0 only while the channel sits
  at sequence 21. The moment it advances to 22, the script walks past the "up to date"
  branch into the `linux-asahi` gate, fails with **exit 2**, and `omarchy-update` line 58
  turns that into an abort of the entire update. Detection off means that step is skipped
  and cannot abort anything.

So it is a trade: detection off means Omarchy itself never updates; detection on means
system updates break the day Omarchy does. **Off is the better default**, and the script
stays here for the day the bundle actually needs moving.

When that day comes, in preference order:

1. Install the six new packages by hand, reusing the script's own verification
   (download + `gpg --verify` against key `5983B1CA…5B5959` + sha256 vs the signed
   manifest), then update the state file. Detection can stay off.
2. Enable detection, and wrap `omarchy-update-asahi-bundle` so an unsatisfiable hardware
   gate returns **3** instead of 2 — `omarchy-update` treats 3 as "channel unavailable,
   deferred" and continues.

## Cleared landmines

- **Migration `1787560726.sh`** re-runs `install/hardware/pacman.sh` under
  `sudo env OMARCHY_PATH=…`, which strips `OMARCHY_PROC_ROOT`. Harmless either way: all
  94 migrations are applied (`~/.local/state/omarchy/migrations`, 0 pending), and that
  script has **no x86 branch** — it only *adds* a signed `[omarchy]` aarch64 repo when
  detection succeeds, and does nothing otherwise.
- **`stable-mirror.omarchy.org`** is only reachable through `omarchy-refresh-pacman`,
  which nothing in the update path calls.
- **Keyring gate**: `omarchy-update-keyring` requires the Omarchy trusted fingerprint
  `40DFB630…CAC571` in the pacman keyring. Verified present.

## Standing constraints

- **Snapshot before any update attempt.**
  `prlctl snapshot "Omarchy 4" --name pre-update-<date>` from the Mac.
- **Do not run `omarchy-setup-direct-boot`.** Gated on the same detection, and it is
  bootloader territory for real Macs. Menu-only; nothing in the update path reaches it.
- **Do not install `linux-asahi`.**
