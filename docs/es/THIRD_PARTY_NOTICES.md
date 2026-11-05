# THIRD_PARTY_NOTICES — Avisos de terceros

[English](../en/THIRD_PARTY_NOTICES.md) · Español · [简体中文](../THIRD_PARTY_NOTICES.md)

Materiales de terceros distribuidos con este repositorio, y sus obligaciones de atribución, licencia y cumplimiento. El código del propio repositorio (parches, `toolkit/`, documentación) se publica bajo GPL-3.0-or-later.

## Avisos de terceros

### Lista de componentes

| Componente | Versión/hash | Origen (upstream) | Licencia | Uso | Titular del copyright | Obligaciones de cumplimiento | Fecha de verificación |
|---|---|---|---|---|---|---|---|
| avbtool | AOSP | android.googlesource.com (platform/external/avb) | MIT | `toolkit/avb/avbtool.py`, distribuido con el repositorio; lo invocan los scripts de firma AVB | The Android Open Source Project | Conservar el aviso de copyright y de licencia (en la cabecera del archivo) | 2026-11-04 |
| herald-core | Véase el repositorio | github.com/CharlesGool/herald-core | GPL-3.0-or-later, etc. (véase el repositorio) | `patches/required/general/herald-core` es una copia sincronizada de su `patch/` (obra del autor de este repositorio, no un tercero externo) | CharlesGool | Igual que herald-core | 2026-11-04 |

### Textos de licencia

- Este repositorio: GPL-3.0-or-later; el texto completo está en `LICENSE`.
- avbtool: MIT; el texto completo del copyright y la licencia está en la cabecera de `toolkit/avb/avbtool.py`.

### Disponibilidad del código fuente

Este repositorio distribuye código fuente de parches, scripts de build y documentación, todo en forma de código fuente, sin obligaciones adicionales de suministro de código. Los productos del build (imagen system, paquete 9008) no están en este repositorio.

### Revisión de cumplimiento

- Componentes copyleft: el propio repositorio, GPL-3.0-or-later. `avbtool.py` (MIT) es compatible con GPL-3.0.
- **Componentes propietarios no incluidos en el repositorio**: el SDK de Megvii necesario para el desbloqueo facial, y el material de la página de educación facial de Pixel (`face_education_lottie.json`, `face_settings.mp4`), son material propietario; están excluidos mediante `.gitignore` y el usuario debe proporcionarlos (véase el README de cada `patches/required/tangorpro/<base>/faceunlock`). Las herramientas de build externas (Android NDK, apktool, dex2jar, xdelta3, etc.) tampoco están en el repositorio, y el usuario debe proporcionarlas.
