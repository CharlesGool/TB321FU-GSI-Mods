# HISTORY — History

English · [Español](../es/HISTORY.md) · [简体中文](../HISTORY.md)

- V1–V66: manual workflow, each version edited directly on top of the previous version's file tree.
- 2026 reorganization: the same changes were turned into "rebuild everything from the original materials with a single command", i.e. this repo's patches plus the build framework.
- 2026-11-03: split from the data project directory into a sibling project. The data directory is located via `TB321FU_DATA` or the sibling `tb321fu_pixelos_15_tangorpro_ap3a.241005.015`.
- 2026-11-05: `user-v1.4` (V133) anchor official release archived. The engine is replaced with herald-core V1.5, which removes SOTER; no functional updates. Also fixes the false `WILL_FALLBACK` report from `spoof set`, and adds the off-by-default system_server injection experiment (P2.0). Cleaned up test-v1.3.1..6.
