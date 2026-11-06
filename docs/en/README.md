# TB321FU-GSI-Mods

English · [Español](../es/README.md) · [简体中文](../../README.md)

[![License](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](../../LICENSE)

Docs: [Design](DESIGN.md) · [Patch spec](../MODULE-SPEC.md) · [Changelog](CHANGELOG.md) · [Maintenance log](LOG.md) · [History](HISTORY.md) · [Third-party notices](THIRD_PARTY_NOTICES.md)

All the changes needed to run a Pixel GSI on the Lenovo Legion Y700 Gen 3 (TB321FU). **One small patch per folder.** Each patch has its own identity file, rationale document, and apply script, and patches do not depend on each other. Dependencies are declared and handled automatically at build time. Pick whichever patches you want.

This repo lives inside the GSI project folder `tb321fu_pixelos_15_tangorpro_ap3a.241005.015/` (much of what is in that project was made specifically for this base build). It is a reorganized version of the manual V1–V66 workflow: the same changes, but rebuilt from the original materials with a single command instead of editing the previous version's file tree each time. For how the project folder is laid out, see the `README.md` one level up.

## How to build

A flash package = original materials + apply the selected patches in order + package:

```
GSI base ──apply system patches──→ system image + vbmeta_system ─┐
Stock boot ─apply firmware patches→ boot set (boot/vbmeta/…)  ────┼─→ 9008 data-preserving flash package (7z)
Stock 9008 package ───────────────────────────────────────────────┘
```

```bash
make list                           # list all patches and which ones this build will include
make build                          # build the system image + vbmeta_system + boot set into out/tb321fu-a15/
make 9008 NOTE="version note"       # all three steps: system + boot set + 9008 package, output in out/tb321fu-a15/
```

`make build` is `toolkit/build.sh`. It puts the GSI base and stock firmware into the same workspace, applies patches in order from one list (system changes edit the tree, boot changes produce boot.img, and changes that touch both are done in one pass), then packages everything together. `make 9008` is `toolkit/build-9008.sh`: it runs build and then `toolkit/flash9008/make_9008_patch.sh`. For details on the 9008 package, see [docs/FLASH-9008.md](../FLASH-9008.md). For AVB re-signing, see [docs/AVB-RESIGN.md](../AVB-RESIGN.md).

## Selecting patches

You do not need to edit `device.conf`. Selection rules are passed at build time, and the system, boot set, and 9008 package steps all use the same selection:

```bash
make 9008 WITHOUT=tango NOTE="no 32-bit"                              # drop an entire category
make build WITHOUT=refresh-control,hotspot-6ghz-unlock                # drop a few
make build WITH=optional/refresh-auto-switch                          # add ones that are off by default
make 9008 WITH=app-backup,custom-font NOTE="…"                        # add advanced features that are off by default
make 9008 PROFILE=no-tango NOTE="…"                                   # use a preset
make menu SAVE=my-build                                               # open the checkbox menu and save the selection as preset my-build
make info P=battery                                                   # show what a patch depends on and what depends on it
```

Rule syntax: patch name (`battery`, `brightness/hbm-unlimited`), category folder (`slim`, `brightness`), wildcard (`hotspot-*`, `spoof/*`), or `all`.

- **Default**: `MODS` in `device.conf` lists all optional patches for this device (both those that change system and those that change boot), and also sets the execution order. The default selection is `MODS` minus whatever is in `MODS_OFF`.
- **Off by default**: advanced and non-native features (`app-backup`, `custom-font`, `devopts-hide/*`, `statusbar-netspeed`, `game-mode`, `perf/*`, `herald-readonly-shell`, `herald-ush`), unconventional modifications (`brightness/hbm-unlimited`), and research and diagnostic patches. Add them with `WITH=` if you want them.
- **Presets**: `devices/<device>/profiles/<name>.txt`, one `+rule` or `-rule` per line. `-all` means start from nothing and pick. Existing presets: `no-tango`, `no-herald`, `slim-only`.
- **Dependencies are handled automatically**: when you select a patch, the patches listed in its `REQUIRES` in `patch.conf` are pulled in automatically, and `WANTS` are applied too (soft dependencies; for example, a patch that modifies a jar pulls in `stale-boot-image`). Patches that register changes to an artifact (the Wi-Fi APEX, boot) automatically pull in the assemble patch that packages that artifact. A patch you explicitly excluded is not pulled back in, and patches that depend on it are dropped as well. The build lists all of these at startup.
- **Order**: patches always run in the order given by `MODS`. Before building, check that order against each patch's `REQUIRES`, `AFTER`, and `BEFORE` in `patch.conf`.
- The selection for each build is recorded in `SELECTION.txt` in the output directory. When building the 9008 package, the build checks that the system and boot set were made from the same selection.

## What a patch looks like

```
patches/optional/brightness/hbm-unlimited/      regular patch
  patch.conf   identity: name, one-line description, stage, dependencies, ordering constraints, runtime switches (read by patch selection and by checks)
  README.md    rationale: why it changes things, what it changes, inputs, notes for switching base builds, pitfalls, how to verify
  apply.sh     makes the changes on the working tree
  files/ src/ patches/   files copied into the image as-is / source and build scripts / patches applied to the base build

patches/required/general/hardware-fix/bluetooth-fix/                 combined patch: several parts fix the same thing or are too tightly coupled, so they can only be applied all together or not at all
  patch.conf   same as above
  README.md    overall description and parts table
  apply.sh     external dependencies + run_parts (runs the parts in numeric order, each in its own subshell)
  parts/001.profile-props/        part.sh + README.md + files/…   each part's own implementation and rationale
  parts/002.a2dp-offload-policy/
  parts/003.sco-call-fix/
```

`patch.conf` says what a patch is and how it relates to others. The README explains how it is implemented. For the format and rules, see [docs/MODULE-SPEC.md](../MODULE-SPEC.md).

## Patch overview

All 47 patches (31 applied by default, including 1 pulled in automatically) are listed in **[patches/README.md](../../patches/README.md)**. The list is split into tables by `required/general` (required, general fixes), `required/tangorpro` and similar (required, specific to one base build; the folder name is the base build ID prefix and the patch only runs when it matches), `optional`, and `debug`. The tables are generated by `toolkit/gen-index.sh` from each `patch.conf`, with numbers and Chinese names. By purpose (★ = off by default):

| Purpose | Patches |
|---|---|
| Slimming (removal only) | `slim/pixel-leftovers`, `slim/old-vndk`, `slim/pixel-hardware` (Pixel Tablet only), `slim/google-slim` (tiered slimming of Google apps) (a generic script plus each patch's own lists/), `slim/gsi-traces` (leftovers from Mystic/phh) |
| Restoring device identity / removing traces | `identity`, `debug-off`, `gsi-hide`, `rw-system-tmpfs`, `kernel-builder-string` (modifies boot) |
| SELinux | `selinux/fix` (SELinux fix, changes system and boot together), `selinux/shell-logcat` |
| Fixing GSI problems / restoring stock behavior | `auto-brightness-fix` (auto-brightness fix), `rotation-fix`, `bluetooth-fix`, `hotspot-ui-fix`, `build-consistency-dialog-fix`, `macro-camera-fix` |
| Stock features | `zuicamera` (Lenovo camera), `faceunlock` (face unlock), `battery` (battery protection, charge limit, bypass), `6ghz-fix` (country code + 6GHz band fix, required), `hotspot-control` (custom hotspot + commands, optional), `wifi-apex-assemble` (APEX packaging), `hotspot-6ghz-unlock` |
| Root-free core and spoofing | `herald-core` (core: command channel, pairing, plugin interface), `attestation-fix` (key attestation: keymint engine + default identity, hooked into the core), ★`spoof/global-pif`, ★`spoof/app-spoof`, ★`herald-readonly-shell` |
| System features | `navbar-hide`, `adaptive-refresh-fix` (adaptive refresh rate fix), `refresh-control` (refresh rate control), ★`refresh-auto-switch` (switches per app / by battery level), `tango` (32-bit APKs) |
| Advanced features (all ★) | `app-backup`, `custom-font`, `devopts-hide`, `statusbar-netspeed`, `game-mode`, `perf` (performance tuning), `perf-game-boost` |
| Unconventional | ★`brightness/hbm-unlimited` |
| Finishing / packaging | ★`stale-boot-image` (pulled in automatically when a jar-modifying patch is selected), `boot-assemble` (writes boot.img) |
| Debugging / research / diagnostics (`debug/`, all off by default) | `debug/shell-logcat`, `debug/adb-on-boot`, `debug/diag-boot-camera-log`, `debug/herald-readonly-shell`, `debug/herald-ush`, `debug/herald-zygisk-timing-probe`, `debug/herald-zygisk-fork-observer`; the debug-leaning ★`overlay-idmap-reset` stays in optional |

How things are split: fixes for the same problem that only work together are one combined patch (internal `parts/001.xxx` …). Pieces that each work on their own, where a user might want only one, are separate. "Similar names" do not count as a category: the hotspot entry UI and hotspot behavior are separate, and brightness and refresh rate are separate. Unconventional changes are always their own patch.

## Switching base builds

When switching GSI source or Android version (for example, an Android 16 GSI from Pixel Fold), survey first:

```bash
make survey BASE_GSI=/path/to/new-base.img      # run each patch separately on the new base (needs sudo, slow)
```

The output is `out/survey-<base name>/report.md`. For each patch it says whether it works, whether it fails (with the reason the patch reports), or whether it cannot be used because of its dependencies. It also produces a suggested preset `profile.txt` with the unusable items removed. After reviewing, copy it to `devices/<device>/profiles/` to use it with `PROFILE=`, then fix the broken patches one by one.

Why the survey results can be trusted: patches are written to check their preconditions first and, if those are not met, to fail with an explanation. They never silently skip. Removal patches that find something absent from the base build only log a line and do not count as failures. The most affected patches are the smali patches that modify jars and APEXes (face unlock, Wi-Fi, spoofing, fonts, netspeed, per-app hiding, and so on). Switching to a new major Android version usually means redoing those patches against the new base. Patches in the firmware stage only depend on the stock firmware, so switching the GSI does not affect them. A patch that runs but behaves wrongly (for example, a property name changed in the new version) still needs to be checked on a real device.

## Testing

```bash
make unit                                  # unit tests for the broker/heraldctl plugins (no device, no root needed)
toolkit/tests/test-patch-meta.sh           # checks that each patch's patch.conf matches its apply.sh, that the order is correct, and that the overview is up to date
make test                                  # runs each patch separately on a clean base (needs sudo)
toolkit/tests/test-modules.sh devices/tb321fu-a15/device.conf --leave-out   # removes each patch once and runs everything else
```

`test-modules.sh` layers overlayfs over the read-only mounted base, so every test starts from a clean base without copying several GB.

## Directory layout

| Directory | Contents |
|---|---|
| `patches/` | All patches. One folder per patch (for those with an `apply.sh`). Category folders are only for grouping and selecting batches at once |
| `toolkit/` | Build framework: `build.sh` (build), `build-9008.sh` (build + 9008 package), `select.sh` (view and pick patches), `gen-index.sh`, `run-module.sh` (run a single patch), `lib/` (shared functions for patches, selection logic in `select.sh`), `tests/`, `avb/`, `apex/`, `vendor-bind/`, `flash9008/` |
| `devices/<device>/` | `device.conf` (patch directories, paths, signing), `conf.d/*.conf` (parameters for each patch), `profiles/` (selection presets) |
| `docs/` | `MODULE-SPEC.md` (how to write patches), `FLASH-9008.md`, `AVB-RESIGN.md`. `topics/` holds background notes on several older groups (Wi-Fi APEX, root-free core, boot landing…) |
| `private/` | Not in the repo: private binaries, keybox, signing keys (see "Inputs" in each patch's README) |
| `out/` | Build output (not in the repo) |

## Standalone releases

`hotspot-control`/`hotspot-6ghz-unlock`, `navbar-hide`, `herald-core` + `spoof/`, and `boot-assemble` plus `toolkit/` are written so they are not tied to TB321FU (device-specific values all live in `device.conf`). They may be split out and published on GitHub later. The herald engine binary and the keybox are private. When published, only the scripts, sepolicy, and docs will be released.

## Relation to the project folder

The parent of this repo is the GSI project folder (`device.conf` picks up `OLD` from it automatically). Large files and private items live there and are not copied into the repo:

| Location in project | Contents |
|---|---|
| `inputs/` | Build inputs: `base/` (original Mystic zip), `base-fw-a15/` (stock boot, vbmeta, etc.), `tools/` (xdelta3, pif-toolchain, etc.) |
| `releases/` | Release builds: images and reports, 9008 patch packages |
| `legacy/` | Build scripts and sources for the manual V1–V66 workflow (`gsi/`, `overlay/`, `faceunlock/`…). `gsi/strong/herald-payload` is herald's private payload. `faceunlock/incoming/tools` (dex2jar/r8/apktool) is still used by the build |
| `doc/` | Backend API doc (`herald-backend-api.md`) and research notes. `doc/history/` holds old READMEs, FIXES, TEST, and release notes |

## Requirements

- Build host: Linux, with `sudo`, Python 3, Android build-tools 35, and the external tools listed in the "Inputs" column of each patch's README (apktool, xdelta3, etc.; bring your own).
- Flashing: a Qualcomm 9008 (EDL) tool, on Windows or Linux.

## Installation

This repository produces flash packages; it is not software you install directly. The 9008 package made by `make 9008` is flashed with `flash.bat` (wipes data) or `flash_keep_data.bat` (keeps data), which are inside the package.

## Uninstall

Flash back the stock 9008 base firmware.

## Acknowledgements

AVB signing uses AOSP's `avbtool`. Full third-party credits and licenses are in [docs/THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

This repository itself is released under GNU GPL v3.0 or later (`GPL-3.0-or-later`); the full text is in [LICENSE](../../LICENSE). `toolkit/avb/avbtool.py`, distributed with this repo, comes from AOSP and is under the `MIT` license (its copyright and license notice are in the file header). See [docs/THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details.
