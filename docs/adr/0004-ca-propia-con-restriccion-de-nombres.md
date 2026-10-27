# ADR 0004: HTTPS con CA propia restringida a la red local

| Campo | Valor |
|---|---|
| Estado | Aceptada |
| Fecha | 2026-10-25 (registrada 2026-10-26) |

## Contexto

Con HTTP plano, un atacante en la misma red (ARP spoofing) podía inyectar
JavaScript en la página y robar la clave guardada en el iPad, anulando el HMAC.
Las CA públicas no emiten certificados para IPs privadas.

## Decisión

La app crea una CA propia (ECDSA P-256, 10 años) con `nameConstraints` críticas
que solo permiten `192.168.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12` y `.local`, y
emite con ella el certificado del servidor (825 días, renovación automática).
Los dispositivos instalan la CA una vez mediante un perfil de configuración.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| HTTP plano | Inyección de código por un atacante en la red |
| Certificado autofirmado sin CA | Hay que reinstalarlo en cada renovación o cambio de IP |
| CA sin restricción de nombres | Si su clave se filtra, permitiría suplantar cualquier sitio de internet en el iPad |
| Let's Encrypt con dominio propio | Requiere dominio, DNS público y exponer nombres internos |

## Consecuencias

- **Positivas:** TLS real en la LAN; la CA robada no sirve fuera de la red local; renovar el certificado del servidor no exige tocar los dispositivos.
- **Negativas:** paso de instalación manual; la descarga inicial va por HTTP (puerto 8788) y se verifica comparando la huella.
- **Seguimiento:** v1.1 abre el 8788 solo en modo emparejamiento; v2.1 añadirá el rango de la VPN a las restricciones.
