# RFC 0001: Acceso al panel desde internet

| Campo | Valor |
|---|---|
| Estado | **Propuesto** |
| Autor | Jordan Guzman |
| Fecha | 2026-10-26 |
| Decisión relacionada | [ADR 0009](../adr/0009-estrategia-de-acceso-por-internet.md) |

## Resumen

El panel funciona hoy solo en la red local. Este documento analiza si puede
usarse desde internet sin correr riesgos, desde cuatro puntos de vista
(ciberseguridad, arquitectura, desarrollo y una persona sin conocimientos
técnicos). Concluye:

1. **Nunca** exponer los puertos del panel directamente a internet.
2. El acceso remoto debe pasar por una **red privada superpuesta (VPN de malla,
   p. ej. Tailscale/WireGuard)** que autentique al dispositivo *antes* de que
   llegue al panel.
3. Antes de eso hay que **endurecer el panel en la red local** (versión 1.1) y
   **reemplazar el servidor de desarrollo de Python** por uno de grado de
   producción (versión 2.0).

## Contexto

- El panel controla el teclado de la Mac mediante el permiso de Accesibilidad.
- El cliente principal es un iPad Air (2013) con iOS 12, que no recibe parches
  de seguridad desde 2023.
- La autenticación actual (HMAC con reto, clave por dispositivo, TLS con CA
  propia) es sólida para una red de confianza.
- El servidor usa `http.server` de Python. Su propia documentación advierte que
  **no está pensado para producción**: solo implementa comprobaciones de
  seguridad básicas.

## Qué está en juego

Antes de elegir una solución hay que entender el **impacto** si algo falla.

Con una clave robada, un atacante puede pulsar *Seleccionar todo*, *Copiar*,
*Pegar* y *Enter*. Si en la Mac está abierta una Terminal y el portapapeles
contiene un comando, eso equivale a **ejecutar código en la Mac**. El impacto de
un compromiso es por tanto **crítico**, aunque las acciones parezcan inocentes.

> Regla que guía todo el análisis: cuanto mayor el impacto, más capas deben
> fallar antes de que el atacante llegue al panel.

## Análisis por punto de vista

### 1. Ingeniero de ciberseguridad (piensa como atacante)

**Qué ocurre al abrir un puerto en internet:** en minutos lo encuentran
escáneres automáticos (Shodan, Censys, botnets). No hace falta que nadie te
busque: barren todo internet continuamente.

| Vector | Hoy (red local) | Si se expone el puerto |
|---|---|---|
| Fuerza bruta de la clave | Inviable (~99 bits, bloqueos) | Sigue inviable |
| Denegación de servicio | Bloqueo global de 5 min (molestia) | **Cualquiera en el mundo** puede mantener el panel bloqueado indefinidamente |
| Vulnerabilidades del servidor HTTP o TLS | Solo atacables desde tu red | **Atacables por todo internet**; `http.server` no está endurecido |
| Huella digital (*fingerprinting*) | Poco relevante | Revela que hay una Mac con un panel de control |
| Robo de la clave en el iPad | Requiere acceso al iPad | Igual, pero el iPad con iOS 12 navegando por internet es más fácil de comprometer |
| Página HTTP del certificado (8788) | Necesaria para emparejar | **Inaceptable**: sirve contenido sin cifrar a internet |

**Principios que aplica:**

- **Confianza cero (*zero trust*):** no confiar en la red; verificar la
  identidad del dispositivo **antes** de que pueda hablar con la aplicación.
- **Defensa en profundidad:** varias capas independientes. La red privada
  autentica al equipo, TLS cifra y HMAC autentica cada acción. Que falle una no
  basta para el atacante.
- **Mínima superficie de ataque:** lo que no escucha en internet no se puede
  atacar desde internet.
- **Mínimo privilegio:** el permiso de Accesibilidad es enorme. Las acciones
  deben seguir siendo una lista cerrada y, a futuro, configurables por
  dispositivo.

**Veredicto:** la exposición directa queda descartada. Con una red privada
superpuesta, el panel **no escucha en internet**: la VPN cifra y autentica al
dispositivo con criptografía moderna (WireGuard) y solo equipos autorizados
llegan a ver el puerto.

### 2. Arquitecto de software

Criterios: superficie de ataque, dependencias externas, costo, compatibilidad
con el iPad, complejidad de operación y recuperación ante fallos.

| Opción | Cómo funciona | Superficie expuesta | Compatible con iPad iOS 12 | Costo | Veredicto |
|---|---|---|---|---|---|
| **A. Abrir puerto en el router** | Internet → router → Mac:8787 | Todo internet | Sí | 0 | ❌ Descartada: máxima exposición |
| **B. Proxy inverso propio + autenticación** (Caddy/nginx con mTLS u OAuth) | Internet → proxy en la Mac → panel | Todo internet (el proxy) | Parcial | 0 | ❌ Mueve el problema al proxy; requiere puerto abierto y mantenimiento experto |
| **C. Túnel gestionado con control de identidad** (Cloudflare Tunnel + Access) | Internet → Cloudflare (inicio de sesión con SSO/MFA) → túnel saliente → panel | La de Cloudflare; ningún puerto abierto en casa | Dudoso (páginas de inicio de sesión modernas en Safari 12) | Gratis para uso personal | ⚠️ Alternativa válida: depende de un tercero que ve el tráfico descifrado |
| **D. Red privada superpuesta** (Tailscale o WireGuard) | Dispositivo ⇄ túnel cifrado punto a punto ⇄ Mac | Ninguna para el panel | **No** (requiere iOS 15+) | Gratis para uso personal | ✅ **Recomendada** |
| **E. Servidor intermediario propio en la nube** | Mac y dispositivo se conectan a un relé | El relé | Sí | Servidor mensual | ❌ Construir y operar un servicio de internet es más riesgo que el problema |

**Por qué D:**

- **Ningún puerto abierto** en el router; la Mac solo inicia conexiones salientes.
- **Autenticación de red fuerte** antes de llegar a la aplicación (claves
  WireGuard por equipo, cuenta con MFA).
- **Cifrado de extremo a extremo:** el proveedor coordina, pero no puede leer el
  tráfico (a diferencia de C).
- **Revocación central:** quitar un equipo de la red lo deja fuera al instante.
- **Sin cambios de protocolo** en el panel: se mantiene HMAC + TLS (defensa en
  profundidad).

**Consecuencia aceptada:** el iPad Air con iOS 12 **no puede** usar el acceso
remoto. Seguirá siendo un panel de la red local. Para usar el panel fuera de
casa hará falta un dispositivo con iOS 15 o posterior.

**Cambios necesarios en la plataforma para D:**

- El servidor debe aceptar el rango de direcciones de la VPN (`100.64.0.0/10`,
  espacio compartido CGNAT), que hoy rechaza por no ser "privado".
- La restricción de nombres de la CA debe incluir ese rango y el dominio de la
  VPN; si no, el certificado no será válido por la VPN.
- La app debe mostrar claramente por qué interfaces escucha el panel.

### 3. Desarrollador

| Hallazgo | Riesgo | Propuesta |
|---|---|---|
| `http.server` no es de grado de producción | Errores de análisis HTTP, límites de recursos débiles | Migrar el servidor a Swift con el framework Network de Apple, dentro de la app (v2.0). Elimina además la dependencia de Python |
| Sin pruebas unitarias ni integración continua | Una regresión de seguridad puede pasar inadvertida | Pruebas unitarias + GitHub Actions en cada cambio (incluido en este cambio) |
| API sin versión | Cambios incompatibles rompen a los clientes | Prefijo `/v1/` en la próxima versión mayor |
| El bloqueo global es un vector de denegación de servicio | Un tercero en la red bloquea el panel | Retroceso exponencial por IP y retirar el bloqueo global (v1.1) |
| El puerto 8788 (HTTP) está siempre abierto | Superficie innecesaria | Abrirlo solo durante un «modo emparejamiento» con tiempo límite (v1.1) |
| Botones definidos en el código | Cada cambio exige recompilar y conceder permisos | Botones configurables, firmados y guardados en el Llavero (v1.2) |

### 4. Una persona que no sabe cómo funciona internet

Pregunta legítima: *«¿Puedo usar mis botones fuera de casa sin que nadie entre
a mi Mac?»*

**Explicación con una analogía:**

- **Abrir un puerto** es como dejar la puerta de la calle abierta con una
  cerradura muy buena: todos los que pasan pueden intentar abrirla, empujarla o
  bloquearla, todo el día.
- **Una VPN privada** es como un pasillo secreto entre tu iPhone y tu casa que
  solo existe para tus aparatos. Desde la calle no hay puerta que encontrar.

**Lo que necesita esta persona de la app:**

- Un indicador claro: **«Visible desde internet: No»**.
- No tener que configurar el router nunca.
- Avisos comprensibles: *«Estás en una red Wi-Fi que no es la de tu casa; el
  panel se apagó por seguridad.»*
- Saber que si pierde el teléfono, un botón (*Revocar*) lo deja fuera.

## Plan propuesto

| Versión | Tema | Contenido |
|---|---|---|
| **1.1.0** | Endurecer la red local | Modo «redes de confianza» (el panel solo se enciende en redes Wi-Fi aprobadas); retroceso exponencial por IP en lugar de bloqueo global; puerto 8788 solo en modo emparejamiento; versión visible en la app y en `/estado`; pruebas de integración |
| **1.2.0** | Mínimo privilegio | Botones configurables desde la app; permisos de acciones por dispositivo |
| **2.0.0** | Servidor de producción | Servidor en Swift (Network.framework) dentro de la app; API `/v1/`; sin Python |
| **2.1.0** | Acceso remoto | Soporte de red privada superpuesta (rango CGNAT y dominio de la VPN en la CA y en los filtros); indicador de exposición; guía de configuración |

Cada versión se publica con su entrada en el CHANGELOG, su release en GitHub y
los ADR de las decisiones que tome.

## Alternativas consideradas y descartadas

Ver la tabla de la sección de arquitectura. La opción C (Cloudflare Tunnel +
Access) queda documentada como **plan B** si en el futuro se necesita acceso
desde un navegador sin instalar nada, aceptando que un tercero termina el TLS.

## Preguntas abiertas

- ¿Qué dispositivo con iOS 15+ se usará fuera de casa?
- ¿Tailscale (gestionado, más simple) o WireGuard autoalojado (sin terceros, más
  mantenimiento)?

## Referencias

- [Documentación de `http.server`: advertencia de seguridad](https://docs.python.org/3/library/http.server.html)
- [Tailscale: requisitos de iOS](https://tailscale.com/download/ios)
- [WireGuard en la App Store](https://apps.apple.com/app/id1441195209)
- [RFC 6598: espacio de direcciones compartido (100.64.0.0/10)](https://www.rfc-editor.org/rfc/rfc6598)
