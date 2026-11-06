# TB321FU-GSI-Mods

[English](../en/README.md) · Español · [简体中文](../../README.md)

[![License](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](../../LICENSE)

Documentación: [Diseño](DESIGN.md) · [Especificación de parches](../MODULE-SPEC.md) · [Cambios](CHANGELOG.md) · [Registro de mantenimiento](LOG.md) · [Historial](HISTORY.md) · [Avisos de terceros](THIRD_PARTY_NOTICES.md)

Todas las modificaciones para ejecutar Pixel GSI en la Lenovo Legion Y700 Gen 3 (TB321FU). **Una carpeta por cada parche pequeño**; cada parche incluye su propio archivo de identidad, su documento de principios y su script de aplicación. Los parches no dependen unos de otros (las dependencias están indicadas y se resuelven automáticamente al compilar), así que puede elegir los que quiera.

Este repositorio está dentro de la carpeta del proyecto GSI `tb321fu_pixelos_15_tangorpro_ap3a.241005.015/` (muchas cosas del proyecto están hechas específicamente para esta imagen base). Es la versión reorganizada del flujo manual de V1–V66: los mismos cambios, pero en lugar de "modificar directamente el árbol de archivos de la versión anterior", ahora todo se reconstruye desde los materiales originales con un solo comando. La organización de la carpeta del proyecto se explica en el `README.md` del directorio superior.

## Cómo compilar

El paquete de flasheo = materiales originales + aplicar en orden los parches seleccionados + empaquetar:

```
Imagen base GSI ──aplicar parches de system──→ imagen system + vbmeta_system ─┐
boot original ────aplicar parches de firmware─→ conjunto de boot (boot/vbmeta/…) ─┼─→ paquete 9008 que conserva los datos (7z)
Paquete 9008 original ────────────────────────────────────────────────────────┘
```

```bash
make list                           # ver todos los parches y cuáles se aplicarán esta vez
make build                          # genera la imagen system + vbmeta_system + conjunto de boot, en out/tb321fu-a15/
make 9008 NOTE="nota de versión"    # los tres pasos juntos: system + conjunto de boot + paquete 9008; salida en out/tb321fu-a15/
```

`make build` equivale a `toolkit/build.sh`: la imagen base GSI y el firmware original se colocan en el mismo espacio de trabajo y los parches se aplican uno por uno según una lista (los que modifican system cambian el árbol de archivos, los que modifican boot generan boot.img, y los que modifican ambos se hacen de una sola vez); al final se empaqueta todo. `make 9008` equivale a `toolkit/build-9008.sh`: tras el build, ejecuta `toolkit/flash9008/make_9008_patch.sh`. Los detalles del paquete 9008 están en [docs/FLASH-9008.md](../FLASH-9008.md), y el re-firmado AVB en [docs/AVB-RESIGN.md](../AVB-RESIGN.md).

## Seleccionar parches

No hace falta editar `device.conf`. Las reglas de selección se pasan al compilar; los tres pasos (system, conjunto de boot y paquete 9008) usan la misma:

```bash
make 9008 WITHOUT=tango NOTE="sin 32 bits"                     # quitar una categoría completa
make build WITHOUT=refresh-control,hotspot-6ghz-unlock                   # quitar varios
make build WITH=optional/refresh-auto-switch                  # añadir los que no se aplican por defecto
make 9008 WITH=app-backup,custom-font NOTE="…"               # añadir funciones avanzadas que no se aplican por defecto
make 9008 PROFILE=no-tango NOTE="…"                            # usar un preajuste
make menu SAVE=my-build                                        # menú de selección; guardar como preajuste my-build
make info P=battery                                            # ver de qué depende un parche y quién depende de él
```

Formato de las reglas: nombre de parche (`battery`, `brightness/hbm-unlimited`), carpeta de categoría (`slim`, `brightness`), comodines (`hotspot-*`, `spoof/*`), `all`.

- **Por defecto**: `MODS` en `device.conf` es la lista completa de parches opcionales de este dispositivo (los que modifican system y los que modifican boot están ahí) y también define el orden de ejecución; si quita los de `MODS_OFF`, obtiene la selección por defecto.
- **No se aplican por defecto**: funciones avanzadas o no nativas (`app-backup`, `custom-font`, `devopts-hide/*`, `statusbar-netspeed`, `game-mode`, `perf/*`, `herald-readonly-shell`, `herald-ush`), modificaciones no convencionales (`brightness/hbm-unlimited`) y los de investigación y diagnóstico. Si los quiere, añádalos con `WITH=`.
- **Preajustes**: `devices/<dispositivo>/profiles/<nombre>.txt`, una línea por regla, `+regla` / `-regla`; `-all` significa empezar desde cero. Disponibles: `no-tango`, `no-herald`, `slim-only`.
- **Dependencias automáticas**: si elige un parche, se incluyen automáticamente los que aparecen en `REQUIRES` de su `patch.conf`, y también los de `WANTS` (dependencias blandas; por ejemplo, un parche que modifica un jar incluye `stale-boot-image`). Si un parche registra cambios en un artefacto (el APEX de Wi-Fi, boot), se incluye automáticamente el parche de ensamblado que lo empaqueta. Los parches que usted quitó explícitamente no se vuelven a añadir, y los que dependen de ellos también se quitan. Al inicio del build se listan todos estos casos.
- **Orden**: siempre se ejecuta en el orden de `MODS`; antes de compilar, compruebe ese orden según `REQUIRES`/`AFTER`/`BEFORE` del `patch.conf` de cada parche.
- La selección de cada compilación se guarda en `SELECTION.txt` del directorio de salida; al generar el paquete 9008 se verifica que system y el conjunto de boot se hayan hecho con la misma selección.

## Estructura de un parche

```
patches/optional/brightness/hbm-unlimited/      parche normal
  patch.conf   identidad: nombre, descripción en una frase, fase, dependencias, requisitos de orden y interruptores en tiempo de ejecución (los leen la selección de parches y las comprobaciones)
  README.md    principio: por qué se cambia, qué se cambia, entradas, precauciones al cambiar de imagen base, trampas conocidas y cómo verificar
  apply.sh     hace los cambios sobre el árbol de trabajo
  files/ src/ patches/   archivos que se copian tal cual a la imagen / código fuente y scripts de build / parches que se aplican sobre la imagen base

patches/required/general/hardware-fix/bluetooth-fix/                 parche combinado: varias partes arreglan lo mismo o están muy ligadas; solo se pueden aplicar todas o ninguna
  patch.conf   igual que arriba
  README.md    descripción general y tabla de partes
  apply.sh     dependencias externas + run_parts (ejecuta las partes en orden numérico, cada una en su propio subshell)
  parts/001.profile-props/        part.sh + README.md + files/…   implementación y principio de cada parte
  parts/002.a2dp-offload-policy/
  parts/003.sco-call-fix/
```

`patch.conf` indica "qué es y qué relación tiene con otros", y el README indica "cómo está implementado". El formato y las reglas están en [docs/MODULE-SPEC.md](../MODULE-SPEC.md).

## Resumen de parches

En total hay 47 parches (31 se aplican por defecto, incluido 1 que se añade automáticamente). La tabla completa está en **[patches/README.md](../../patches/README.md)**, separada en `required/general` (obligatorio · corrección general), `required/tangorpro`, etc. (obligatorio · limitado a una imagen base concreta; el nombre de la carpeta es el prefijo del ID de la imagen base y solo se ejecuta si coincide), `optional` (opcional) y `debug` (depuración). Se genera con `toolkit/gen-index.sh` a partir de cada `patch.conf`, e incluye números y nombres en chino. Por uso (★ = no se aplica por defecto):

| Uso | Parches |
|---|---|
| Recorte (solo elimina cosas) | `slim/pixel-leftovers`, `slim/old-vndk`, `slim/pixel-hardware` (exclusivo de Pixel Tablet), `slim/google-slim` (recorte escalonado de apps de Google) (script común + lists/ propios de cada parche), `slim/gsi-traces` (restos dejados por Mystic/phh) |
| Restauración del modelo / eliminar rastros | `identity`, `debug-off`, `gsi-hide`, `rw-system-tmpfs`, `kernel-builder-string` (modifica boot) |
| SELinux | `selinux/fix` (corrección de SELinux, modifica system y boot a la vez), `selinux/shell-logcat` |
| Corregir fallos de GSI / restaurar lo original | `auto-brightness-fix` (corrección del brillo automático), `rotation-fix`, `bluetooth-fix`, `hotspot-ui-fix`, `build-consistency-dialog-fix`, `macro-camera-fix` |
| Funciones originales | `zuicamera` (cámara de Lenovo), `faceunlock` (desbloqueo facial), `battery` (protección de batería / límite / bypass), `6ghz-fix` (código de país + corrección de la banda de 6 GHz, obligatorio), `hotspot-control` (personalización y comandos del punto de acceso, opcional), `wifi-apex-assemble` (empaquetado del APEX), `hotspot-6ghz-unlock` |
| Núcleo sin root y suplantación | `herald-core` (núcleo: canal de comandos, emparejamiento, interfaz de plugins), `attestation-fix` (atestación de claves: motor keymint + identidad por defecto, conectado al núcleo), ★`spoof/global-pif`, ★`spoof/app-spoof`, ★`herald-readonly-shell` |
| Funciones del sistema | `navbar-hide`, `adaptive-refresh-fix` (corrección de la tasa de refresco adaptativa), `refresh-control` (control de la tasa de refresco), ★`refresh-auto-switch` (cambio automático según la app o la batería), `tango` (APK de 32 bits) |
| Funciones avanzadas (todas ★) | `app-backup`, `custom-font`, `devopts-hide`, `statusbar-netspeed`, `game-mode`, `perf` (ajuste de rendimiento), `perf-game-boost` |
| No convencional | ★`brightness/hbm-unlimited` |
| Cierre / empaquetado | ★`stale-boot-image` (se incluye automáticamente si elige un parche que modifica un jar), `boot-assemble` (escribe boot.img) |
| Depuración / investigación / diagnóstico (`debug/`, por defecto ninguno se aplica) | `debug/shell-logcat`, `debug/adb-on-boot`, `debug/diag-boot-camera-log`, `debug/herald-readonly-shell`, `debug/herald-ush`, `debug/herald-zygisk-timing-probe`, `debug/herald-zygisk-fork-observer`; el parche ★`overlay-idmap-reset`, más orientado a depuración, se mantiene en optional |

Criterio de agrupación: lo que corrige lo mismo y solo queda completo si se combina va en un único parche (internamente `parts/001.xxx` …); lo que puede funcionar por separado y el usuario podría querer solo una parte se separa; "que el nombre se parezca" no es un criterio (la UI de entrada del punto de acceso y el comportamiento del punto de acceso van por separado; el brillo y la tasa de refresco van por separado); y las modificaciones no convencionales van en un parche aparte.

## Cambiar de imagen base

Al cambiar de fuente GSI o de versión de Android (por ejemplo, la GSI de Android 16 de Pixel Fold), primero haga un reconocimiento:

```bash
make survey BASE_GSI=/ruta/nueva-base.img      # ejecuta cada parche por separado sobre la nueva base (requiere sudo, es lento)
```

Genera `out/survey-<nombre-de-la-base>/report.md`: para cada parche indica si funciona, si no funciona (con el motivo que informa el propio parche) o si no funciona por dependencia; también hay un `profile.txt` sugerido sin los parches que no funcionan. Una vez revisado, cópielo a `devices/<dispositivo>/profiles/` y podrá usarlo con `PROFILE=`; después corrija uno por uno los que no funcionan.

Por qué el resultado del reconocimiento es fiable: los parches están escritos para "comprobar primero las condiciones previas y, si no se cumplen, dar error explicando la causa", así que nunca omiten nada en silencio; los parches de eliminación que encuentran algo que en la base ya no existe solo registran una línea en el log y no cuentan como fallo. Los más afectados son los parches de smali que modifican jar / APEX (rostro, Wi-Fi, suplantación, fuentes, velocidad de red, ocultación de apps…); al cambiar de versión mayor de Android normalmente hay que rehacer los parches según la nueva base. Los parches de la fase de firmware solo dependen del firmware original, así que cambiar de GSI no les afecta. Lo que funciona pero no se comporta bien (por ejemplo, si un nombre de propiedad cambió en la nueva versión) aún hay que comprobarlo en un dispositivo real.

## Pruebas

```bash
make unit                                  # pruebas unitarias de los plugins broker/heraldctl (no toca el dispositivo real ni requiere root)
toolkit/tests/test-patch-meta.sh           # comprueba que el patch.conf y el apply.sh de cada parche coinciden, que el orden es correcto y que el índice general está actualizado
make test                                  # prueba cada parche por separado sobre una imagen base limpia (requiere sudo)
toolkit/tests/test-modules.sh devices/tb321fu-a15/device.conf --leave-out   # quita cada parche una vez y ejecuta todos los demás
```

`test-modules.sh` monta la imagen base en solo lectura y superpone overlayfs; cada prueba parte de una imagen base limpia, sin copiar varios GB.

## Directorios

| Directorio | Contenido |
|---|---|
| `patches/` | Todos los parches. Un parche por carpeta (la que tiene `apply.sh`); las carpetas de categoría solo sirven para agrupar y para seleccionar un lote de una vez |
| `toolkit/` | Marco de build: `build.sh` (compilar), `build-9008.sh` (compilar + paquete 9008), `select.sh` (ver/elegir parches), `gen-index.sh`, `run-module.sh` (ejecutar un solo parche), `lib/` (funciones comunes para los parches, lógica de selección de `select.sh`), `tests/`, `avb/`, `apex/`, `vendor-bind/`, `flash9008/` |
| `devices/<dispositivo>/` | `device.conf` (carpetas de parches, rutas, firmas), `conf.d/*.conf` (parámetros de cada parche), `profiles/` (preajustes de selección) |
| `docs/` | `MODULE-SPEC.md` (cómo escribir parches), `FLASH-9008.md`, `AVB-RESIGN.md`; `topics/` contiene notas de contexto de algunos grupos antiguos (APEX de Wi-Fi, núcleo sin root, aterrizaje de boot…) |
| `private/` | No va al repositorio: binarios privados, keybox, claves de firma (ver la sección "Entradas" del README de cada parche) |
| `out/` | Salida del build (no va al repositorio) |

## Lo que se puede publicar por separado

`hotspot-control`/`hotspot-6ghz-unlock`, `navbar-hide`, `herald-core` + `spoof/`, y `boot-assemble` junto con `toolkit/` están escritos sin depender del TB321FU (los valores específicos del dispositivo están en `device.conf`), así que más adelante podrían separarse y publicarse en GitHub. Los binarios del motor de herald y el keybox son privados; al publicarlo solo se subirían los scripts, sepolicy y la documentación.

## Relación con la carpeta del proyecto

El directorio superior del repositorio es el proyecto GSI (`OLD` en `device.conf` lo toma automáticamente). Los archivos grandes y privados están allí y no se copian al repositorio:

| Ubicación en el proyecto | Contenido |
|---|---|
| `inputs/` | Entradas del build: `base/` (zip original de Mystic), `base-fw-a15/` (boot, vbmeta originales, etc.), `tools/` (xdelta3, pif-toolchain, etc.) |
| `releases/` | Versiones publicadas: imágenes e informes, paquetes 9008 |
| `legacy/` | Scripts de build y código fuente del flujo manual V1–V66 (`gsi/`, `overlay/`, `faceunlock/`…). `gsi/strong/herald-payload` es el payload privado de herald, y `faceunlock/incoming/tools` contiene dex2jar/r8/apktool; el build todavía los usa |
| `doc/` | Documentación de la API del backend (`herald-backend-api.md`) y notas de investigación; `doc/history/` contiene los README, FIXES, TEST y notas de publicación antiguos |

## Requisitos

- Equipo de build: Linux, `sudo`, Python 3, Android build-tools 35, y las herramientas externas indicadas en la sección "Entradas" del README de cada parche (apktool, xdelta3, etc.), que debe proporcionar usted mismo.
- Flasheo: herramienta Qualcomm 9008 (EDL), en Windows o Linux.

## Instalación

Este repositorio genera paquetes de flasheo; no es un programa que se instale directamente. El paquete 9008 que genera `make 9008` se flashea en el dispositivo con `flash.bat` (borra los datos) o `flash_keep_data.bat` (conserva los datos), según cuál venga incluido en el paquete.

## Desinstalación

Basta con volver a flashear el paquete 9008 original de fábrica.

## Agradecimientos

La firma AVB usa `avbtool` de AOSP. Las atribuciones y licencias completas de terceros están en [docs/THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Licencia

Este repositorio se publica bajo GNU GPL v3.0 o posterior (`GPL-3.0-or-later`); el texto completo está en [LICENSE](../../LICENSE). El archivo `toolkit/avb/avbtool.py` incluido en el repositorio proviene de AOSP y se distribuye bajo licencia `MIT` (el copyright y el aviso de licencia están en su cabecera). Más detalles en [docs/THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
