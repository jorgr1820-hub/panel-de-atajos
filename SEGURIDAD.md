# Seguridad del Panel de atajos

El panel permite que un dispositivo controle la Mac (teclas, apps, música), así
que se diseñó pensando en cómo lo atacaría alguien.

## Qué protege y cómo

| Ataque | Defensa |
|---|---|
| Alguien en el mismo Wi‑Fi escucha el tráfico | HTTPS (TLS 1.2+) con una CA propia. Además, cada toque se firma con HMAC‑SHA256: la clave nunca viaja |
| Alguien en el Wi‑Fi se hace pasar por la Mac (ARP spoofing) e inyecta código en la página para robar la clave | El dispositivo solo confía en el certificado de la CA del panel; un impostor no tiene su clave privada |
| Grabar un toque y repetirlo (replay) | Cada firma usa un reto aleatorio de un solo uso, que caduca en 30 s y solo vale para el equipo que lo pidió |
| Adivinar la clave | 20 caracteres aleatorios (~99 bits) + bloqueo tras 8 fallos por equipo o 25 en total durante 5 min |
| Saturar el panel pidiendo retos | Máximo 8 retos pendientes por equipo y 64 en total |
| Acceso desde internet | Solo se aceptan IPs privadas de la red local |
| Una página web maliciosa abierta en la Mac o en el iPad intenta usar el panel (CSRF, DNS rebinding) | Se exige firma con la clave; se rechazan nombres de host que no sean IPs locales o `.local`; se comprueba el origen |
| Incrustar el panel en otra página (clickjacking) o inyectar scripts | Cabeceras CSP estrictas, `X-Frame-Options: DENY`, sin HTML dinámico |
| Pedir al panel que ejecute un comando | Solo existen 9 acciones fijas; nada de lo recibido se ejecuta |
| Usar la administración desde la red | La API de administración escucha solo en `127.0.0.1:8789` y exige un token nuevo en cada arranque |
| Leer las claves del disco | Las claves y el certificado están en el Llavero de macOS, no en archivos. Los secretos se entregan al servidor por la entrada estándar (no aparecen en `ps`) |
| Alguien usa tu Mac desbloqueada para ver o crear claves | La app pide Touch ID o la contraseña de la Mac para mostrar, crear o cambiar claves. El código QR se cierra solo a los 2 minutos |
| Malware modifica el servidor para aprovechar el permiso de Accesibilidad de la app | La app comprueba las huellas SHA‑256 de los archivos del servidor (fijadas en el binario al compilar) y se niega a arrancar si cambiaron. Python se ejecuta con `-I` (ignora variables y carpetas del usuario) y con un entorno limpio. Se usan `/usr/bin/openssl` y `/usr/bin/python3`, que macOS protege |
| Roban la clave privada de la CA | La CA tiene restricción de nombres: solo vale para IPs privadas y nombres `.local`. No sirve para suplantar sitios de internet en tus dispositivos |
| La Mac cambia de IP | El certificado del servidor se renueva solo con la misma CA; no hay que reinstalar nada |
| El registro revela actividad | El registro vive solo en memoria y se borra al apagar el panel o cerrar la app |

## Límites conocidos (riesgo aceptado)

- **El dispositivo emparejado es de confianza.** Quien tenga el iPad desbloqueado puede usar el panel. Para quitarle el acceso usa **Revocar** o **Nueva clave**.
- **Malware con acceso total a tu usuario** podría, con suficiente esfuerzo, atacar la propia app o el Llavero. Ninguna app de usuario se defiende por completo de eso; mantén macOS actualizado y activa el firewall.
- **Las firmas son ad‑hoc.** Cada vez que se recompila, macOS pide de nuevo el permiso de Accesibilidad y el acceso al Llavero. Eso es intencional: un binario distinto no hereda los permisos.
- **iOS 12 no permite guardar la clave fuera del almacenamiento del navegador** del iPad. Si borras los datos de Safari, hay que emparejar de nuevo.

## Reportar una vulnerabilidad

Si encuentras un problema de seguridad, **no abras un issue público**. Usa
[*Report a vulnerability*](https://github.com/jorgr1820-hub/panel-de-atajos/security/advisories/new)
en la pestaña *Security* del repositorio. Incluye los pasos para reproducirlo y
el impacto que esperas.

## Recomendaciones

1. Activa el firewall de macOS (Ajustes del Sistema → Red → Firewall).
2. Instala el certificado en cada dispositivo y **comprueba la huella** contra la de la app.
3. Revoca los dispositivos que ya no uses.
4. Si sospechas que algo se comprometió: **Nueva clave** en ese dispositivo y, si es grave, **Crear certificado nuevo**.
