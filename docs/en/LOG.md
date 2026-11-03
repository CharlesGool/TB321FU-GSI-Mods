# LOG — Maintenance Log

English · [Español](../es/LOG.md) · [简体中文](../LOG.md)

## Records

Version changes are in [CHANGELOG.md](CHANGELOG.md). Historical requirements and old handover notes are in [HISTORY.md](HISTORY.md).

## Defects

None at the moment.

## Limitations

- Face unlock and the face education page animations depend on proprietary components (the Megvii face SDK and Pixel stock assets). These are not distributed with the repo and must be supplied by the user.
- When switching to a new major Android version, smali patches that modify jars or APEXes usually need to be redone against the new base build. A build that succeeds still has to be verified on a real device for correct behavior.

## Decisions

| Date | Decision | Status | Reason |
|---|---|---|---|
| 2026-11-03 | Repo split from the data project directory into a sibling project | Accepted | Easier to maintain and release on its own; the data directory is located via `TB321FU_DATA` or the sibling path |
| 2026-11-04 | Proprietary components (Megvii SDK, Pixel face assets) are not distributed | Accepted | Proprietary material cannot be redistributed publicly; users supply it themselves, and the docs explain how |

## Handover

No work in progress. The current branch is `main`, in sync with `origin/main`.
