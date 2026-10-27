# ADR 0008: Versionado semántico y flujo con Pull Requests

| Campo | Valor |
|---|---|
| Estado | Aceptada |
| Fecha | 2026-10-26 |

## Contexto

Hasta v1.0.0 los cambios se hacían directamente en `main`, sin pruebas
automáticas. En un proyecto con impacto de seguridad, una regresión puede pasar
inadvertida y no hay forma clara de saber qué versión está instalada.

## Decisión

- **Versionado semántico** (`MAYOR.MENOR.PARCHE`): mayor para cambios
  incompatibles (p. ej. API o reinstalar la CA), menor para funciones nuevas
  compatibles, parche para correcciones. La versión vive en el archivo `VERSION`.
- **Ramas de vida corta** desde `main` (`feat/`, `fix/`, `docs/`, `chore/`,
  `security/`), integradas con **Pull Request**.
- **`main` protegida:** solo se integra con PR y con la integración continua en verde.
- **Commits convencionales** (`feat:`, `fix:`, `docs:`, `test:`, `ci:`, `chore:`, `security:`).
- **Cada versión:** entrada en `CHANGELOG.md`, etiqueta `vX.Y.Z` y release en GitHub.
- **Integración continua** en GitHub Actions: pruebas unitarias, verificación de la firma JS y compilación de la app.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| Seguir en `main` directamente | Sin revisión ni pruebas antes de integrar |
| Git Flow (ramas `develop`, `release`) | Demasiado proceso para un proyecto pequeño |
| Versionado por fecha | No comunica si un cambio rompe compatibilidad |

## Consecuencias

- **Positivas:** historial legible; cada versión es reproducible; las pruebas bloquean regresiones.
- **Negativas:** algo más de proceso por cambio.
- **Seguimiento:** el procedimiento está en `CONTRIBUTING.md`.
