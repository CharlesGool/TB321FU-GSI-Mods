# CHANGELOG — Change Log

English · [Español](../es/CHANGELOG.md) · [简体中文](../CHANGELOG.md)

## user-v1.3(V132)— 2026-11-04

### Changed
- herald-core upgraded to V1.3 (working directory regression fix). The authentication engine is replaced with a new build that includes security hardening.
- Patch set unchanged from user-v1.2.

## user-v1.2(V129)— 2026-11-03

### Fixed
- Bluetooth: `vendor-bind` now adds the SELinux permissions for `update_engine`.

### Changed
- Rebuilt with the test label removed (`ro.tb321fu.mod_version=user-v1.2`).
