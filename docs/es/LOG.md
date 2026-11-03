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

## Traspaso

No se han encontrado trabajos en curso. Rama actual `main`, sincronizada con `origin/main`.
