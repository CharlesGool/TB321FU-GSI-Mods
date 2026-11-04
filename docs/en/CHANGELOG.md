# CHANGELOG — Change Log

English · [Español](../es/CHANGELOG.md) · [简体中文](../CHANGELOG.md)

## user-v1.4(V133)— 2026-11-05

Anchor official release after SOTER removal, **no functional updates** (patch set same as user-v1.3).

### Changed
- The engine is replaced with herald-core V1.5 (SOTER removed + AGPL dropped). keymint/inject behavior is unchanged; three-green on real device verified.

### Fixed
- `attestation-fix`: false `WILL_FALLBACK` report from the broker's `spoof set`. The prediction now derives release from fingerprint, consistent with `herald-global-pif.sh` (profiles for directory-style models without a separate release field no longer falsely report fallback).

### Added (off by default)
- `attestation-fix`: experimental gated launcher for `inject --target system_server` (one-shot flag `/data/local/tmp/herald_ss_inject`, consumed on read, never kills system_server). Used for P2.0 verification, not triggered by default. On real device, the injection into system_server was rejected by SELinux (rc=1, safe with no side effects); P2 is shelved.

## user-v1.3(V132)— 2026-11-04

### Changed
- herald-core upgraded to V1.3 (working directory regression fix). The authentication engine is replaced with a new build that includes security hardening.
- Patch set unchanged from user-v1.2.

## user-v1.2(V129)— 2026-11-03

### Fixed
- Bluetooth: `vendor-bind` now adds the SELinux permissions for `update_engine`.

### Changed
- Rebuilt with the test label removed (`ro.tb321fu.mod_version=user-v1.2`).
