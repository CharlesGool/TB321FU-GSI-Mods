# DESIGN — Design

English · [Español](../es/DESIGN.md) · [简体中文](../DESIGN.md)

## Design goals

- All the changes needed to run a Pixel GSI on the Lenovo Legion Y700 Gen 3 (TB321FU), **rebuilt from the original materials with a single command**, replacing the manual workflow of editing the previous version's file tree each time.
- One small patch per folder, each with its own identity file, rationale document, and apply script. Patches are independent of each other; dependencies are declared and handled automatically at build time; pick whichever patches you want.
- Patches are decoupled from the base build. When switching GSI source or Android version, use `make survey` to evaluate each patch's applicability.

## Architecture

Build = original materials + apply the selected patches in order + package. The GSI base goes through the system patches to yield the system image and vbmeta_system. The stock boot goes through the firmware patches to yield the boot set. Both are combined with the stock 9008 package into the data-preserving flash package.

Top-level directories and their roles:

| Directory | Role |
|---|---|
| `patches/` | All patches, one folder per patch (each with `apply.sh`). Category folders are only for grouping and batch selection |
| `toolkit/` | Build framework: `build.sh`, `build-9008.sh`, `select.sh`, `gen-index.sh`, `lib/`, `tests/`, `avb/`, `flash9008/`, etc. |
| `devices/<device>/` | `device.conf` (patch directories, paths, signing), `conf.d/*.conf` (per-patch parameters), `profiles/` (selection presets) |
| `docs/` | Project docs. `topics/` holds background notes from several older efforts |

Build output (`out/`) and private files (`private/`) are not in the repo. For how to write patches, see [docs/MODULE-SPEC.md](../MODULE-SPEC.md).

## Design constraints

- Patch order always follows `MODS` in `device.conf`. Before building, check it against each `patch.conf`'s `REQUIRES`/`AFTER`/`BEFORE`.
- Patch selection does not change `device.conf`. It uses build-time selection rules (`PROFILE`/`WITH`/`WITHOUT`), and the three steps (system, boot, 9008) use the same selection.
- Removal patches that find something not present in the base build only log it and do not fail. Patches whose preconditions are not met fail with an explanation of why; they never silently skip.

## Data design

Build inputs come from the sibling data project directory (`OLD` in `device.conf`; `TB321FU_DATA` can override it): base builds, stock firmware, tools, release builds (`releases/`), and leftovers of the manual `legacy/` workflow. Official release builds are named `user-vX.Y` and marked with `KEEP` for protection (see `toolkit/clean-releases.sh`).

## Extending

To add a patch, create a new folder with `patch.conf` (identity, dependencies, order, switches), `README.md` (rationale), and `apply.sh` (changes). The rules are in [docs/MODULE-SPEC.md](../MODULE-SPEC.md).
