# ADR 0009: Estrategia de acceso por internet

| Campo | Valor |
|---|---|
| Estado | Propuesta |
| Fecha | 2026-10-26 |
| Análisis | [RFC 0001](../rfc/0001-acceso-por-internet.md) |

## Contexto

Se quiere usar el panel fuera de casa. Un compromiso equivale a controlar el
teclado de la Mac (impacto crítico). El servidor actual no es de grado de
producción y el iPad principal tiene iOS 12, sin soporte para VPN modernas.

## Decisión

- Los puertos del panel **nunca** se expondrán directamente a internet.
- El acceso remoto se hará mediante una **red privada superpuesta** (Tailscale o
  WireGuard), manteniendo TLS y HMAC como capas adicionales.
- Requisitos previos, en este orden: endurecimiento en LAN (v1.1), servidor de
  producción en Swift (v2.0) y soporte de la VPN (v2.1).

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| Abrir puertos en el router | Expone el panel a escáneres de todo internet |
| Proxy inverso propio | Traslada la exposición al proxy y requiere mantenimiento experto |
| Cloudflare Tunnel + Access | Válida como plan B; un tercero ve el tráfico descifrado y su inicio de sesión puede no funcionar en Safari 12 |
| Relé propio en la nube | Operar un servicio de internet añade más riesgo del que resuelve |

## Consecuencias

- **Positivas:** ningún puerto abierto en casa; autenticación de red antes de llegar al panel; revocación central.
- **Negativas:** el iPad Air con iOS 12 queda limitado a la red local; dependencia de un coordinador de VPN (si se elige Tailscale).
- **Seguimiento:** pasa a «Aceptada» al iniciar v2.1; requiere ampliar la CA y los filtros al rango `100.64.0.0/10`.
