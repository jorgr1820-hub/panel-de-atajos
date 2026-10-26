#!/bin/bash
# Pruebas de seguridad del Panel de atajos. Úsalo con el panel encendido,
# después de cada cambio:   ./pruebas.sh
#
# No necesita claves ni el token de administración: comprueba que todo lo que
# un atacante podría intentar sin ellos se rechaza. Cada ejecución suma 2
# intentos fallidos a la IP de esta Mac (se bloquea con 8 en 5 minutos; el
# iPad no se ve afectado).
set -uo pipefail
cd "$(dirname "$0")"

IP=""
for i in en0 en1 en2 en3 en4 en5 en6 en7 en8; do IP=$(ipconfig getifaddr $i 2>/dev/null) && [ -n "$IP" ] && break; done
APP="Panel de atajos.app"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
OK=0; MAL=0

prueba() {  # prueba "descripción" "obtenido" "esperado"
  if [ "$2" = "$3" ]; then printf '  ✅ %s\n' "$1"; OK=$((OK + 1))
  else printf '  ❌ %s (esperado %s, obtenido %s)\n' "$1" "$3" "$2"; MAL=$((MAL + 1)); fi
}
codigo() { curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$@"; }

if ! lsof -nP -iTCP:8787 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "El panel está apagado: enciéndelo desde la app y vuelve a ejecutar."; exit 1
fi
echo "Panel en $IP"

echo "Cifrado"
curl -s -o "$TMP/ca.cer" --max-time 5 "http://$IP:8788/panel-ca.cer"
/usr/bin/openssl x509 -inform der -in "$TMP/ca.cer" -out "$TMP/ca.pem" 2>/dev/null
curl -s -o /dev/null --max-time 5 "https://$IP:8787/"; prueba "HTTPS sin confiar en la CA se rechaza" "$?" "60"
prueba "HTTPS con la CA del panel funciona" "$(codigo --cacert "$TMP/ca.pem" "https://$IP:8787/")" "200"
curl -s -o /dev/null --max-time 5 "http://$IP:8787/"; prueba "HTTP sin cifrar al panel no responde" "$?" "56"
TLS=$(echo | /usr/bin/openssl s_client -connect "$IP:8787" -tls1_1 2>&1 | grep -c 'Cipher is (NONE)\|alert\|wrong version\|no protocols')
prueba "TLS 1.1 (obsoleto) se rechaza" "$([ "$TLS" -gt 0 ] && echo sí || echo no)" "sí"
NC=$(/usr/bin/openssl x509 -in "$TMP/ca.pem" -noout -text | grep -c 'Name Constraints: critical')
prueba "La CA solo vale para la red local (restricción de nombres)" "$NC" "1"
/usr/bin/openssl x509 -in "$TMP/ca.pem" -noout -checkend $((60 * 86400)) >/dev/null
prueba "La CA no vence en los próximos 60 días" "$?" "0"
echo | /usr/bin/openssl s_client -connect "$IP:8787" 2>/dev/null | /usr/bin/openssl x509 -noout -checkend $((60 * 86400)) >/dev/null
prueba "El certificado del servidor no vence en los próximos 60 días" "$?" "0"

echo "Acceso"
S="https://$IP:8787"; C=(--cacert "$TMP/ca.pem")
prueba "Host ajeno (DNS rebinding) se rechaza" "$(codigo "${C[@]}" --resolve "evil.example.com:8787:$IP" https://evil.example.com:8787/ -k)" "403"
prueba "Origen ajeno (CSRF) se rechaza" "$(codigo "${C[@]}" -X POST -H 'Origin: https://evil.example.com' "$S/accion/copiar")" "403"
prueba "Acción sin firma se rechaza" "$(codigo "${C[@]}" -X POST "$S/accion/copiar")" "401"
prueba "Firma inventada se rechaza" "$(codigo "${C[@]}" -X POST -H 'X-Reto: 00' -H 'X-Firma: 00' "$S/accion/copiar")" "401"
prueba "Acción inexistente se rechaza" "$(codigo "${C[@]}" -X POST "$S/accion/rm-rf")" "404"
prueba "Métodos no previstos (PUT) se rechazan" "$(codigo "${C[@]}" -X PUT "$S/")" "405"
prueba "No se sirven archivos internos (server.py)" "$(codigo "${C[@]}" "$S/server.py")" "404"
prueba "No se puede salir de la carpeta (../)" "$(codigo "${C[@]}" --path-as-is "$S/../Info.plist")" "404"

echo "Administración"
curl -s -o /dev/null --max-time 3 "http://$IP:8789/estado"; prueba "La administración no escucha en la red" "$?" "7"
prueba "Administración local sin token se rechaza" "$(codigo http://127.0.0.1:8789/estado)" "403"
prueba "Administración desde un navegador (Origin) se rechaza" "$(codigo -H 'Origin: http://127.0.0.1:8789' -H 'X-Admin: x' http://127.0.0.1:8789/estado)" "403"

echo "Secretos e integridad"
PID=$(lsof -tiTCP:8787 -sTCP:LISTEN | head -1)
prueba "Ningún secreto visible en ps (argumentos y entorno)" "$(ps eww -o command= -p "$PID" | grep -ciE 'admin_token|clave|BEGIN')" "0"
security find-generic-password -s local.jordan.panel-de-atajos -a secretos >/dev/null 2>&1
prueba "Las claves están en el Llavero" "$?" "0"
prueba "No hay claves en archivos (config.json)" "$(ls panel/config.json 2>/dev/null | wc -l | tr -d ' ')" "0"
codesign -v "$APP" 2>/dev/null; prueba "La firma de la app es válida (nada alterado)" "$?" "0"
IGUALES=0
for f in server.py index.html app.js firma.js; do cmp -s "panel/$f" "$APP/Contents/Resources/panel/$f" && IGUALES=$((IGUALES + 1)); done
prueba "La app lleva la última versión del código (si no, ejecuta app/compilar.sh)" "$IGUALES" "4"

echo
echo "Resultado: $OK correctas, $MAL fallidas"
[ "$MAL" -eq 0 ]
