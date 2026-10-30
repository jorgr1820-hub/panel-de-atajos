#!/bin/bash
# Compila "Panel de atajos.app": copia el servidor dentro de la app, fija sus
# huellas SHA-256 en el binario (la app se niega a arrancar si alguien lo
# modifica) y firma la app (ad-hoc).
#
# Ojo: cada compilación cambia la firma, así que macOS pedirá otra vez el
# permiso de Accesibilidad y permitir el acceso al Llavero.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="Panel de atajos.app"
ARCHIVOS=(server.py index.html app.js firma.js)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/panel"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Panel de atajos</string>
  <key>CFBundleDisplayName</key><string>Panel de atajos</string>
  <key>CFBundleIdentifier</key><string>local.jordan.panel-de-atajos</string>
  <key>CFBundleExecutable</key><string>PanelDeAtajos</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>0</string>
  <key>CFBundleShortVersionString</key><string>0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Para enviar las teclas y controlar la música desde tus dispositivos.</string>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
EOF

# La versión sale del archivo VERSION (única fuente de verdad, ver CONTRIBUTING.md).
VERSION=$(tr -d '[:space:]' < VERSION)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
                        -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"

HUELLAS="$(mktemp -d)/Huellas.swift"
{
  echo "// Generado por compilar.sh. No editar."
  echo "let huellasServidor: [String: String] = ["
  for f in "${ARCHIVOS[@]}"; do
    install -m 0444 "panel/$f" "$APP/Contents/Resources/panel/$f"
    echo "    \"$f\": \"$(shasum -a 256 "panel/$f" | cut -d' ' -f1)\","
  done
  echo "]"
} > "$HUELLAS"

swiftc -O -parse-as-library -target arm64-apple-macos14.0 \
  -o "$APP/Contents/MacOS/PanelDeAtajos" app/PanelApp.swift "$HUELLAS"
rm -rf "$(dirname "$HUELLAS")"

codesign --force -s - --identifier local.jordan.panel-de-atajos "$APP"
codesign -v "$APP"
echo "Listo: $APP $VERSION"
