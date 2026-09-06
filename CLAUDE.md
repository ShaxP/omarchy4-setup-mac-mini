# omarchy4-setup-mac-mini

Working notes for installing **Omarchy 4 (Quattro)** in a **Parallels Desktop** VM on a
**Mac Mini M4 Pro** (Apple Silicon, arm64).

## What this repo is for

A scratchpad + knowledge base. Questions get asked here, answers and working
configs get written down so they survive across sessions. There is no application
to build or test.

## Key constraint (verified 2026-09-03)

Official Omarchy is **x86_64 only** — the official ISO will not boot in Parallels on
Apple Silicon, which can only run arm64 guests. Any working setup goes through a
community path:

- Install **Arch Linux ARM** (or an arm64 Archboot environment) as the base, then run
  Omarchy's install source on top of it.
- Chosen source of truth: https://www.reddit.com/r/omarchy/comments/1vrpp7b/40_running_in_parallels/
  (Parallels on Apple Silicon, borrows the aarch64 packages from `maralcbr/omarchy-mx-mac`
  and `maralcbr/omarchy-pkgs`). Worked into a checklist at
  `notes/2026-09-03-omarchy4-parallels-checklist.md`. Reddit is network-blocked here —
  read that URL via Claude in Chrome, not WebFetch/curl.
- Parallels also needs its guest tools (`prl-tools`) for display resize / clipboard;
  Hyprland + Parallels video driver is a known friction point.

## Conventions

- Record confirmed-working steps in `notes/` as dated markdown files.
- Keep any install/fix scripts in `scripts/`, executable, with a comment header saying
  which Omarchy version and Parallels version they were tested against.

## Prior attempt

The user already ran these instructions once on a MacBook Pro (M1 Pro). It worked but was
cumbersome and slow. The goal for the Mac Mini run is fewer dead ends, not more explanation.

## Update status (resolved 2026-09-04)

`omarchy update` completes on this VM. Read `notes/omarchy-update-checklist.md` before
touching anything update-related — it carries the procedure and a per-update findings log.

Two things to know going in:

- Apple Silicon detection fails in Parallels and that is **fine and deliberate**. It is
  not a blocker, and `scripts/enable-arm-detection.sh` is written but intentionally not
  applied. Reasoning: `notes/2026-09-05-apple-silicon-detection.md`.
- Consequence: system packages update, but Omarchy itself stays frozen at the installed
  bundle (`4.0.0.r6673.g5939caf`). Moving it is a manual job.

## Open work

- `IgnorePkg = aquamarine` is held in `/etc/pacman.conf` and in
  `scripts/fix-pacman-arm.sh`, working around an Arch Linux ARM soname lag. Remove from
  both once ALARM rebuilds `hyprland`/`hyprtoolkit` against `so=14`. Last checked
  2026-09-05: not yet, and not imminent. Hold watch log and a check that cannot read a
  stale sync DB are in `notes/omarchy-update-checklist.md`.
