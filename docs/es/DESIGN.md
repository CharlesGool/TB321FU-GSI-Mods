# DESIGN — Diseño

[English](../en/DESIGN.md) · Español · [简体中文](../DESIGN.md)

## Objetivos de diseño

- Todas las modificaciones para ejecutar Pixel GSI en la Lenovo Legion Y700 Gen 3 (TB321FU), **reconstruibles desde los materiales originales con un solo comando**, en sustitución del flujo manual de "modificar directamente el árbol de archivos de la versión anterior".
- Una carpeta por cada parche pequeño, cada una con su archivo de identidad, su documento de principios y su script de aplicación; los parches no dependen unos de otros, las dependencias se declaran y se resuelven automáticamente al compilar, y se aplica el que se quiera.
- Desacoplar los parches de la imagen base: al cambiar de origen de GSI o de versión de Android, use `make survey` para evaluar si cada parche sigue siendo aplicable.

## Arquitectura

Build = materiales originales + aplicar en orden los parches seleccionados + empaquetar: la imagen base GSI pasa por los parches de system y da la imagen system + vbmeta_system; el boot original pasa por los parches de firmware y da el conjunto de boot; y todo se combina con el paquete 9008 original para formar el paquete de flasheo que conserva los datos.

Directorios de nivel superior y sus responsabilidades:

| Directorio | Responsabilidad |
|---|---|
| `patches/` | Todos los parches, una carpeta por parche (con `apply.sh`); las carpetas de categoría solo sirven para clasificar y seleccionar por lotes |
| `toolkit/` | Marco de build: `build.sh`, `build-9008.sh`, `select.sh`, `gen-index.sh`, `lib/`, `tests/`, `avb/`, `flash9008/`, etc. |
| `devices/<dispositivo>/` | `device.conf` (carpetas de parches, rutas, firmas), `conf.d/*.conf` (parámetros de cada parche), `profiles/` (preajustes de selección) |
| `docs/` | Documentación del proyecto; `topics/` contiene notas de contexto de algunos grupos antiguos |

La salida del build (`out/`) y los archivos privados (`private/`) no van al repositorio. El formato de los parches está en [docs/MODULE-SPEC.md](../MODULE-SPEC.md).

## Restricciones de diseño

- El orden de los parches siempre sigue `MODS` de `device.conf`; antes de compilar, compruébelo según `REQUIRES`/`AFTER`/`BEFORE` del `patch.conf` de cada parche.
- La selección de parches no modifica `device.conf`: se usan reglas de selección al compilar (`PROFILE`/`WITH`/`WITHOUT`), y los tres pasos (system, boot y 9008) usan la misma selección.
- Los parches de eliminación que encuentran algo que no existe en la imagen base solo registran un log y no cuentan como fallo; los parches cuyas condiciones previas no se cumplen informan del motivo con un error, sin omitirse en silencio.

## Diseño de datos

Las entradas del build vienen del directorio hermano del proyecto de datos (`OLD` en `device.conf`; se puede sobrescribir con `TB321FU_DATA`): imagen base, firmware original, herramientas, productos de cada versión (`releases/`) y restos del flujo manual en `legacy/`. Los productos de versión oficial se nombran `user-vX.Y` y se protegen con la marca `KEEP` (véase `toolkit/clean-releases.sh`).

## Extensión

Para añadir un parche, cree una carpeta nueva con `patch.conf` (identidad, dependencias, orden, interruptores), `README.md` (principio) y `apply.sh` (cambios). Las reglas están en [docs/MODULE-SPEC.md](../MODULE-SPEC.md).
