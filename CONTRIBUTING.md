# Cómo contribuir

Este documento describe el flujo de trabajo del proyecto. El porqué de cada
regla está en el [ADR 0008](docs/adr/0008-versionado-y-flujo-de-trabajo.md).

## Flujo de trabajo

```
main (protegida) ──●──────────────●──────────── v1.1.0 (etiqueta + release)
                    \            /
 feat/redes-confianza ●──●──●──●   ← Pull Request + CI en verde
```

1. **Crea una rama** desde `main` actualizada:
   ```bash
   git switch main && git pull
   git switch -c feat/descripcion-corta
   ```
   | Prefijo | Para |
   |---|---|
   | `feat/` | Funciones nuevas |
   | `fix/` | Correcciones de errores |
   | `security/` | Correcciones o mejoras de seguridad |
   | `docs/` | Solo documentación |
   | `test/` | Solo pruebas |
   | `ci/` | Integración continua |
   | `chore/` | Mantenimiento |

2. **Haz commits pequeños** con [commits convencionales](https://www.conventionalcommits.org/es/v1.0.0/):
   ```
   feat: modo redes de confianza
   fix(servidor): el reto no caducaba tras reiniciar
   security: retroceso exponencial por IP
   ```
   Cambios incompatibles: añade `!` (`feat!: API /v1/`) y un pie `BREAKING CHANGE:`.

3. **Comprueba localmente** antes de abrir el PR:
   ```bash
   /usr/bin/python3 -m unittest discover -s tests -v
   ./app/compilar.sh      # si tocaste app/ o panel/
   ./pruebas.sh           # con el panel encendido
   ```

4. **Abre un Pull Request** hacia `main` y completa la plantilla. La integración
   continua debe estar en verde para integrar.

5. **Integra con «Squash and merge»** si los commits de la rama son de trabajo
   intermedio, o con «Rebase and merge» si cada commit tiene sentido por sí solo.

## Decisiones de diseño

- Una decisión que cambie la arquitectura, la seguridad o el protocolo necesita
  un **ADR** en `docs/adr/` (copia la [plantilla](docs/adr/0000-plantilla.md)).
- Una decisión grande o con varias alternativas se analiza antes en un **RFC**
  en `docs/rfc/`.

## Versiones y releases

El proyecto usa [versionado semántico](https://semver.org/lang/es/). La versión
está en el archivo [`VERSION`](VERSION).

| Cambio | Versión | Ejemplo |
|---|---|---|
| Incompatible (API, reinstalar la CA, migración manual) | **MAYOR** | 1.4.2 → 2.0.0 |
| Función nueva compatible | **MENOR** | 1.4.2 → 1.5.0 |
| Corrección compatible | **PARCHE** | 1.4.2 → 1.4.3 |

Para publicar una versión:

1. En una rama `chore/release-X.Y.Z`: actualiza `VERSION` y mueve las entradas
   de «Sin publicar» del `CHANGELOG.md` a una sección `[X.Y.Z] - AAAA-MM-DD`.
2. Abre el PR, espera la CI e intégralo.
3. Etiqueta y publica desde `main`:
   ```bash
   git switch main && git pull
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin vX.Y.Z
   gh release create vX.Y.Z --title "vX.Y.Z" --notes-file <(sed -n '/## \[X.Y.Z\]/,/## \[/p' CHANGELOG.md)
   ```

## Seguridad

- **Nunca** incluyas claves, certificados ni `config.json` en un commit. La CI
  busca patrones de secretos y falla si los encuentra.
- Las vulnerabilidades se reportan en privado (ver [SEGURIDAD.md](SEGURIDAD.md)).
- Un cambio en `panel/server.py` que añada acciones, rutas o archivos públicos
  debe actualizar `tests/test_server.py` (`TestSuperficie`): así cualquier
  ampliación de la superficie expuesta es deliberada y revisada.

## Estilo

- Código, comentarios y documentación en español.
- Python: compatible con 3.9 (el de las herramientas de Apple), sin dependencias externas.
- JavaScript del cliente: ES5 (Safari de iOS 12).
- Swift: macOS 14 o posterior.
