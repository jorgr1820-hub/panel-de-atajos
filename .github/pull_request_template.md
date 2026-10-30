## Qué cambia y por qué

<!-- Resume el cambio y el problema que resuelve. Enlaza el issue: "Cierra #N". -->

## Tipo de cambio

- [ ] Función nueva (`feat`)
- [ ] Corrección (`fix`)
- [ ] Seguridad (`security`)
- [ ] Documentación, pruebas o CI
- [ ] Cambio incompatible (requiere versión MAYOR)

## Seguridad

- [ ] No añade acciones, rutas ni archivos públicos, **o** actualicé `TestSuperficie` y lo justifico arriba
- [ ] No incluye claves, certificados ni datos personales
- [ ] Revisé el impacto en el [modelo de amenazas](../SEGURIDAD.md)

## Verificación

- [ ] `python3 -m unittest discover -s tests` en verde
- [ ] `./app/compilar.sh` compila (si toqué `app/` o `panel/`)
- [ ] `./pruebas.sh` en verde con el panel encendido (si toqué `app/` o `panel/`)
- [ ] Probado en el dispositivo (si cambia algo visible)

## Documentación

- [ ] `CHANGELOG.md` actualizado en «Sin publicar»
- [ ] ADR nuevo o actualizado (si cambia una decisión de diseño)
- [ ] README o `docs/` actualizados (si cambia el uso o la API)
