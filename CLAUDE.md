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

## Open work

`omarchy update` does not yet complete on this VM. Current state, findings and next
steps: `notes/handoff-update-troubleshooting.md`. Read it before touching anything
update-related.
