# HISTORY — Historial

[English](../en/HISTORY.md) · Español · [简体中文](../HISTORY.md)

- V1–V66: flujo manual; cada versión se modificaba directamente sobre el árbol de archivos de la versión anterior.
- Reorganización de 2026: los mismos cambios pasan a reconstruirse desde los materiales originales con un solo comando; es decir, los parches y el marco de build de este repositorio.
- 2026-11-03: se independiza del directorio de datos del proyecto como proyecto hermano; el directorio de datos se localiza mediante `TB321FU_DATA` o mediante el proyecto hermano `tb321fu_pixelos_15_tangorpro_ap3a.241005.015`.
- 2026-11-05: versión ancla oficial `user-v1.4` (V133) — el motor pasa a herald-core V1.5 que elimina SOTER, sin actualizaciones de funciones; de paso se corrige el falso `WILL_FALLBACK` de `spoof set` y se añade el experimento de inyección en system_server desactivado por defecto (P2.0). Se limpiaron test-v1.3.1..6.
