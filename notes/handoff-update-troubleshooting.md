# Handoff: `omarchy update` troubleshooting

State as of 2026-09-04, written on the Mac before moving the session into the VM.
Read this plus [the update checklist](omarchy-update-checklist.md) before continuing.

## Where things stand

The VM is fully installed and working (Omarchy 4.0.1-mac.1, desktop, terminal,
5120x1440, clean boot). The open problem is **making `omarchy update` work**.

## What we established

`omarchy update`'s ARM behaviour is gated on `/usr/bin/omarchy-hw-apple-silicon`:

```bash
proc_root="${OMARCHY_PROC_ROOT:-/proc}"
[[ $(uname -m) == "aarch64" ]] &&
  grep -aq 'apple,' "$proc_root/device-tree/compatible" 2>/dev/null
```

**Parallels exposes no device tree** — `/proc/device-tree/` does not exist in the guest —
so this returns non-zero, Omarchy concludes it is on x86, and takes the x86 path. That is
the root cause of the recurring pacman breakage, not any ARM incompatibility:
`omarchy-refresh-pacman` explicitly *refuses* to touch a system it detects as Apple
Silicon.

About fifteen scripts gate on that same check (`grep -rln 'omarchy-hw-apple-silicon'
/usr/bin/ /usr/share/omarchy/`).

## What we did

Installed a shim so detection succeeds, at `/usr/local/bin/omarchy-hw-apple-silicon`:

```bash
#!/bin/bash
[[ $(uname -m) == "aarch64" ]]
```

`/usr/local/bin` precedes `/usr/bin` in both `PATH` and sudo's `secure_path`, so it wins
for root and non-root callers. Verified `exit: 0` both ways.

## Where it stopped

```
/usr/bin/omarchy-update-asahi-bundle: line 49: /proc/device-tree/compatible: No such file or directory
Apple Silicon bundle update: Apple Silicon device tree not found
Something went wrong during the update!
```

**The shim worked** — the dispatcher took the ARM branch, which is why
`omarchy-update-asahi-bundle` ran at all. But that script reads
`/proc/device-tree/compatible` **directly**, not via `omarchy-hw-apple-silicon`, so it
has its own independent check to satisfy.

The update **aborted before touching pacman**. Nothing was damaged.

## Next steps

1. Confirm the baseline is still clean: `sudo pacman -Sy`, `grep -nE '^\\[|^Server' /etc/pacman.conf`
2. Read the failing script — does it honour `OMARCHY_PROC_ROOT` like the detector does?

   ```bash
   grep -n 'OMARCHY_PROC_ROOT\\|device-tree\\|proc_root' /usr/bin/omarchy-update-asahi-bundle
   sed -n '35,70p' /usr/bin/omarchy-update-asahi-bundle
   ```

3. If it does: `OMARCHY_PROC_ROOT=/var/lib/omarchy/vm-proc omarchy update`
   (that fake root already exists and contains `device-tree/compatible` = `apple,parallels-vm`)
4. If it hardcodes `/proc`: find what it *uses* the compatible string for — likely
   extracting an SoC model to select packages. There may be a cleaner way to satisfy it
   than a second shim. Note that files cannot be created under `/proc`, and there is no
   `device-tree` directory to bind-mount onto.

## Constraints to respect

- **Snapshot before any update attempt.** `prlctl snapshot "Omarchy 4" --name pre-update-<date>`
  from the Mac. This is the only real safety net.
- **`scripts/fix-pacman-arm.sh` is now partly wrong.** With detection working,
  `install/hardware/pacman.sh` deliberately adds a signed `[omarchy]` repo on the
  *aarch64* release server. That script strips `[omarchy]` unconditionally and would
  delete it. Treat it as a recovery tool for broken detection, not routine hygiene. It
  needs updating once this is settled.
- **Do not run `omarchy-setup-direct-boot`.** It is gated on the same detection and is
  bootloader territory for real Macs. Menu-only; nothing in the update path reaches it.
- Abort an update immediately on any sign of `stable-mirror.omarchy.org`, `[multilib]`,
  or x86 package downloads.

## When it works

Fill in the Findings log in [the update checklist](omarchy-update-checklist.md), correct
the `fix-pacman-arm.sh` guidance, and fold the shim into the install checklist as a
Phase 6 step — it likely prevents the pacman breakage during install too, which would
remove the single biggest source of friction in the whole process.
