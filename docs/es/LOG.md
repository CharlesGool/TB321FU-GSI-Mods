# LOG — Registro de mantenimiento

[English](../en/LOG.md) · Español · [简体中文](../LOG.md)

## Registros

Los cambios por versión están en [CHANGELOG.md](CHANGELOG.md); los requisitos históricos y los traspasos antiguos, en [HISTORY.md](HISTORY.md).

## Defectos

Ninguno por el momento.

## Limitaciones

- El desbloqueo facial y la animación de la página de educación facial dependen de componentes propietarios (SDK de Megvii, material original de Pixel); no se distribuyen con el repositorio y deben proporcionarse por cuenta propia.
- Al cambiar de versión mayor de Android, los parches smali que modifican jar/APEX normalmente deben rehacerse comparándolos con la nueva imagen base; que el build termine no garantiza que la funcionalidad sea correcta, lo que debe verificarse en un dispositivo real.

## Decisiones

| Fecha | Decisión | Estado | Motivo |
|---|---|---|---|
| 2026-11-03 | El repositorio pasa a ser un proyecto hermano independiente del directorio de datos del proyecto | Aceptada | Facilita el mantenimiento y la publicación por separado; el directorio de datos se localiza con `TB321FU_DATA` o con una ruta hermana |
| 2026-11-04 | No distribuir componentes propietarios (SDK de Megvii, material facial de Pixel) | Aceptada | El material propietario no puede redistribuirse públicamente; pasa a ser responsabilidad del usuario, con documentación al respecto |
| 2026-11-04 | `spoof set` deduce el release a partir del fingerprint | Aceptada | Los perfiles de máquina de tipo directorio no tienen campo de release; la lógica anterior informaba falsamente `WILL_FALLBACK` para panther_beta, etc., lo que no coincidía con el comportamiento del script de arranque |
| 2026-11-04 | El lanzador de inyección en system_server está desactivado por defecto y usa una marca de un solo uso | Aceptada | Inyectar en system_server tiene riesgo alto (bootloop); la marca de consumo único evita la persistencia y nunca se mata system_server |
| 2026-11-05 | Publicar la versión ancla `user-v1.4` y eliminar test-v1.3.x | Aceptada | Tras eliminar SOTER se fija una versión ancla; las 6 versiones test se borran con clean-releases y se conservan las tres versiones oficiales anteriores |
| 2026-11-05 | La única fuente del parche `tango` pasa a ser el repositorio tb321fu-tango-patch; este repositorio conserva una copia sincronizada, que se sincroniza con `make sync-tango` y se comprueba con `make unit` | Aceptada | Igual que herald-core; el parche y la guía de portado ya se publican por separado |
| 2026-11-05 | `FaceUnlockSettingsOverlay.apk` deja de versionarse; el material de educación se toma de ParanoidSense upstream y el APK se compila localmente | Aceptada | El APK contiene material propietario de los ajustes de Pixel, lo que contradice la decisión de no distribuir archivos propietarios; los commits antiguos no se reescriben |
| 2026-11-05 | La única fuente del parche `faceunlock` pasa a ser el repositorio tb321fu-faceunlock-patch (un directorio por base), que se sincroniza con `make sync-faceunlock` y se comprueba con `make unit` | Aceptada | Igual que herald-core y tango; la guía general y la herramienta de módulo siguen en paranoidsense-gsi-port |

## Traspaso

No se han encontrado trabajos en curso. Rama actual `main`, sincronizada con `origin/main`.
