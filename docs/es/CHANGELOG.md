# CHANGELOG — Registro de cambios

[English](../en/CHANGELOG.md) · Español · [简体中文](../CHANGELOG.md)

## user-v1.4(V133)— 2026-11-05

Versión oficial ancla tras eliminar SOTER y limpiar el motor; **sin actualizaciones de funciones** (el conjunto de parches es igual que user-v1.3).

### Cambiado
- El motor pasa a herald-core V1.5 (elimina SOTER + quita la AGPL); el comportamiento de keymint/inject no cambia, y los tres verdes se verificaron en dispositivo real.

### Corregido
- `attestation-fix`: falso aviso `WILL_FALLBACK` en `spoof set` del broker. La predicción ahora deduce el release a partir del fingerprint, en línea con `herald-global-pif.sh` (los perfiles de máquina de tipo directorio sin campo de release propio ya no informan falsamente de un fallback).

### Añadido (desactivado por defecto)
- `attestation-fix`: lanzador experimental con control `inject --target system_server` (marca de un solo uso `/data/local/tmp/herald_ss_inject`, que se consume al leerse; nunca se mata system_server). Es para validar P2.0 y no se activa por defecto. En dispositivo real, la inyección en system_server fue rechazada por SELinux (rc=1, sin efectos secundarios de seguridad); P2 queda aparcado.

## user-v1.3(V132)— 2026-11-04

### Cambiado
- herald-core sube a V1.3 (corrección de regresión del directorio de trabajo); el motor de autenticación cambia a una nueva compilación con endurecimiento de seguridad.
- Conjunto de parches igual que user-v1.2.

## user-v1.2(V129)— 2026-11-03

### Corregido
- Bluetooth: `vendor-bind` añade los permisos de SELinux de `update_engine`.

### Cambiado
- Se recompila sin la etiqueta test (`ro.tb321fu.mod_version=user-v1.2`).
