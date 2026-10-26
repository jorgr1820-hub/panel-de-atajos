// Panel de atajos — app de control para la Mac.
//
// - Guarda las claves de los dispositivos y el certificado en el Llavero de macOS
//   (no en archivos) y pide Touch ID o la contraseña para mostrarlas o generarlas.
// - Arranca el servidor como proceso hijo (así el permiso de Accesibilidad es de
//   esta app) y le pasa los secretos por la entrada estándar.
// - Antes de arrancar, comprueba que los archivos del servidor dentro de la app
//   no fueron modificados (huellas SHA-256 fijadas al compilar, ver Huellas.swift).
//
// Compilar: app/compilar.sh

import AppKit
import ApplicationServices
import CoreImage.CIFilterBuiltins
import CryptoKit
import LocalAuthentication
import Security
import SwiftUI
import SystemConfiguration

let carpetaServidor = Bundle.main.resourceURL!.appendingPathComponent("panel")
let carpetaVieja = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Applications/Panel de atajos/panel")
let admin = "http://127.0.0.1:8789"

// MARK: - Modelos

struct DispositivoGuardado: Codable, Identifiable {
    let id: String
    var nombre: String
    var clave: String
    var creado: String
}

struct TLSGuardado: Codable {
    var caClave: String
    var caCert: String
    var clave: String
    var cert: String
    var nombres: [String]
}

struct Secretos: Codable {
    var dispositivos: [DispositivoGuardado] = []
    var tls: TLSGuardado?
}

struct EstadoDispositivo: Codable, Identifiable {
    let id: String
    let nombre: String
    let ip: String?
    let visto_hace: Double?
    let conectado: Bool
}

struct Estado: Codable {
    let ip: String
    let puerto: Int
    let puerto_cert: Int
    let tls: Bool
    let accesibilidad: Bool
    let dispositivos: [EstadoDispositivo]
}

struct Evento: Codable, Identifiable {
    let seq: Int
    let hora: String
    let texto: String
    var id: Int { seq }
}

struct Eventos: Codable {
    let eventos: [Evento]
    let ultimo: Int
}

struct Revelado: Identifiable {
    let id = UUID()
    let nombre: String
    let clave: String
    let url: String
}

// MARK: - Llavero

enum Llavero {
    static let servicio = "local.jordan.panel-de-atajos"
    static let cuenta = "secretos"

    static func leer() -> Secretos? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: servicio,
                                kSecAttrAccount as String: cuenta,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var r: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return nil }
        return try? JSONDecoder().decode(Secretos.self, from: d)
    }

    static func guardar(_ s: Secretos) throws {
        let datos = try JSONEncoder().encode(s)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: servicio,
                                kSecAttrAccount as String: cuenta]
        var st = SecItemUpdate(q as CFDictionary, [kSecValueData as String: datos] as CFDictionary)
        if st == errSecItemNotFound {
            var nuevo = q
            nuevo[kSecValueData as String] = datos
            nuevo[kSecAttrLabel as String] = "Panel de atajos"
            nuevo[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            st = SecItemAdd(nuevo as CFDictionary, nil)
        }
        guard st == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(st)) }
    }
}

// MARK: - Cifrado

enum Cripto {
    static let alfabeto = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")  // sin 0/O ni 1/I/L

    /// 20 caracteres (~99 bits) con muestreo por rechazo: sin sesgo de módulo.
    static func nuevaClave() -> String {
        var letras: [Character] = []
        let limite = UInt8(256 - 256 % alfabeto.count)
        while letras.count < 20 {
            var b = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, b.count, &b)
            for x in b where x < limite && letras.count < 20 { letras.append(alfabeto[Int(x) % alfabeto.count]) }
        }
        return stride(from: 0, to: 20, by: 5).map { String(letras[$0..<$0 + 5]) }.joined(separator: "-")
    }

    static func hex(_ n: Int) -> String {
        var b = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &b)
        return b.map { String(format: "%02x", $0) }.joined()
    }

    static func huella(pem: String) -> String {
        let b64 = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        guard let der = Data(base64Encoded: b64) else { return "?" }
        return SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    static func sha256(archivo: URL) -> String? {
        guard let d = try? Data(contentsOf: archivo) else { return nil }
        return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }
}

/// Ejecuta un programa del sistema con un entorno limpio. Devuelve el código de
/// salida y lo que escribió.
func correr(_ ruta: String, _ args: [String], entrada: Data? = nil) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: ruta)
    p.arguments = args
    p.environment = ["PATH": "/usr/bin:/bin"]
    let salida = Pipe()
    p.standardOutput = salida
    p.standardError = FileHandle.nullDevice
    let tuberia = Pipe()
    p.standardInput = entrada == nil ? FileHandle.nullDevice : tuberia
    do { try p.run() } catch { return (-1, "") }
    if let entrada {
        tuberia.fileHandleForWriting.write(entrada)
        try? tuberia.fileHandleForWriting.close()
    }
    let datos = salida.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: datos, as: UTF8.self))
}

// MARK: - Certificados (openssl del sistema, protegido por macOS)

enum Certificados {
    struct Fallo: Error { let mensaje: String }

    /// true si el certificado vence dentro de `dias` (o no se puede leer).
    static func vence(_ pem: String, enDias dias: Int) -> Bool {
        let (st, _) = correr("/usr/bin/openssl", ["x509", "-noout", "-checkend", String(dias * 86400)],
                             entrada: Data(pem.utf8))
        return st != 0
    }

    static func nombresLocales() -> [String] {
        var nombres: [String] = []
        if let h = SCDynamicStoreCopyLocalHostName(nil) as String? { nombres.append("DNS:\(h).local") }
        var lista: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&lista) == 0, let primero = lista {
            var p: UnsafeMutablePointer<ifaddrs>? = primero
            while let i = p {
                let nombre = String(cString: i.pointee.ifa_name)
                if nombre.hasPrefix("en"), let dir = i.pointee.ifa_addr, dir.pointee.sa_family == UInt8(AF_INET) {
                    var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(dir, socklen_t(dir.pointee.sa_len), &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST)
                    let ip = String(cString: buf)
                    if !ip.hasPrefix("169.254.") { nombres.append("IP:\(ip)") }
                }
                p = i.pointee.ifa_next
            }
            freeifaddrs(primero)
        }
        return nombres.sorted()
    }

    /// CA propia con restricción de nombres: aunque alguien robara su clave, no
    /// serviría para suplantar sitios de internet en tus dispositivos, solo
    /// direcciones de la red local y nombres .local.
    static func nuevaCA() throws -> (clave: String, cert: String) {
        try enCarpetaTemporal { dir in
            try escribir(dir, "ca.cnf", """
            [req]
            distinguished_name=dn
            prompt=no
            [dn]
            CN=Panel de atajos CA
            O=Panel de atajos \(Cripto.hex(4))
            [ext]
            basicConstraints=critical,CA:TRUE,pathlen:0
            keyUsage=critical,keyCertSign,cRLSign
            nameConstraints=critical,permitted;IP:192.168.0.0/255.255.0.0,permitted;IP:10.0.0.0/255.0.0.0,permitted;IP:172.16.0.0/255.240.0.0,permitted;DNS:.local
            subjectKeyIdentifier=hash
            """)
            try openssl(dir, ["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "ca.key"])
            try openssl(dir, ["req", "-x509", "-new", "-key", "ca.key", "-sha256", "-days", "3650",
                              "-config", "ca.cnf", "-extensions", "ext", "-out", "ca.crt"])
            return (try leer(dir, "ca.key"), try leer(dir, "ca.crt"))
        }
    }

    static func nuevoServidor(caClave: String, caCert: String, nombres: [String]) throws -> (clave: String, cert: String) {
        try enCarpetaTemporal { dir in
            try escribir(dir, "ca.key", caClave)
            try escribir(dir, "ca.crt", caCert)
            try escribir(dir, "srv.cnf", """
            [ext]
            basicConstraints=critical,CA:FALSE
            keyUsage=critical,digitalSignature
            extendedKeyUsage=serverAuth
            subjectAltName=\(nombres.joined(separator: ","))
            authorityKeyIdentifier=keyid
            """)
            try openssl(dir, ["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "srv.key"])
            try openssl(dir, ["req", "-new", "-key", "srv.key", "-subj", "/CN=Panel de atajos", "-out", "srv.csr"])
            try openssl(dir, ["x509", "-req", "-in", "srv.csr", "-CA", "ca.crt", "-CAkey", "ca.key",
                              "-set_serial", "0x" + Cripto.hex(16), "-sha256", "-days", "825",
                              "-extfile", "srv.cnf", "-extensions", "ext", "-out", "srv.crt"])
            return (try leer(dir, "srv.key"), try leer(dir, "srv.crt"))
        }
    }

    private static func enCarpetaTemporal<T>(_ trabajo: (URL) throws -> T) throws -> T {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("panel-" + Cripto.hex(8))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: dir) }
        return try trabajo(dir)
    }

    private static func escribir(_ dir: URL, _ nombre: String, _ texto: String) throws {
        let url = dir.appendingPathComponent(nombre)
        FileManager.default.createFile(atPath: url.path, contents: Data(texto.utf8), attributes: [.posixPermissions: 0o600])
    }

    private static func leer(_ dir: URL, _ nombre: String) throws -> String {
        try String(contentsOf: dir.appendingPathComponent(nombre), encoding: .utf8)
    }

    private static func openssl(_ dir: URL, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        p.arguments = args
        p.currentDirectoryURL = dir
        p.environment = ["PATH": "/usr/bin:/bin"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw Fallo(mensaje: "openssl \(args.first ?? "") falló") }
    }
}

// MARK: - Control del servidor

@MainActor
final class Panel: ObservableObject {
    static let shared = Panel()

    @Published var encendido = false
    @Published var estado: Estado?
    @Published var eventos: [Evento] = []
    @Published var permisoApp = AXIsProcessTrusted()
    @Published var aviso: String?
    @Published var avisoCA: String?
    @Published var secretos = Secretos()

    private var proceso: Process?
    private var token = ""
    private var ultimo = 0
    private var reiniciando = false

    var huellaCA: String { secretos.tls.map { Cripto.huella(pem: $0.caCert) } ?? "—" }

    private init() {
        let opciones = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        permisoApp = AXIsProcessTrustedWithOptions(opciones)
        secretos = Llavero.leer() ?? Secretos()
        migrarArchivoViejo()
        encender()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in await Panel.shared.actualizar() }
        }
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            Task { @MainActor in Panel.shared.revisarCertificados() }
        }
    }

    /// Versiones anteriores guardaban las claves en config.json: se pasan al
    /// Llavero y el archivo se sobrescribe y se borra.
    private func migrarArchivoViejo() {
        let archivo = carpetaVieja.appendingPathComponent("config.json")
        guard let datos = try? Data(contentsOf: archivo) else { return }
        struct Viejo: Codable { struct D: Codable { let id: String; let nombre: String; let clave: String; let creado: String? }
                                let dispositivos: [D]? }
        if let v = try? JSONDecoder().decode(Viejo.self, from: datos) {
            for d in v.dispositivos ?? [] where !secretos.dispositivos.contains(where: { $0.id == d.id }) {
                secretos.dispositivos.append(.init(id: d.id, nombre: d.nombre, clave: d.clave, creado: d.creado ?? ""))
            }
        }
        do {
            try Llavero.guardar(secretos)
            try Data(repeating: 0, count: datos.count).write(to: archivo)
            try FileManager.default.removeItem(at: archivo)
        } catch {
            aviso = "No se pudo pasar config.json al Llavero: \(error.localizedDescription)"
        }
    }

    /// Crea la CA la primera vez y renueva el certificado del servidor si cambió
    /// la IP o el nombre de la Mac, o si vence en menos de 60 días (los
    /// dispositivos no tienen que reinstalar nada). Si la que vence es la CA
    /// (dura 10 años), se crea otra y hay que reinstalar el perfil.
    private func prepararCertificados() throws {
        let nombres = Certificados.nombresLocales()
        var tls = secretos.tls
        if let t = tls, Certificados.vence(t.caCert, enDias: 60) {
            tls = nil
            avisoCA = "Se renovó la CA del panel porque iba a vencer: reinstala el perfil en tus dispositivos."
        }
        if tls == nil {
            let ca = try Certificados.nuevaCA()
            tls = TLSGuardado(caClave: ca.clave, caCert: ca.cert, clave: "", cert: "", nombres: [])
        }
        if tls!.nombres != nombres || tls!.cert.isEmpty || Certificados.vence(tls!.cert, enDias: 60) {
            let s = try Certificados.nuevoServidor(caClave: tls!.caClave, caCert: tls!.caCert, nombres: nombres)
            tls!.clave = s.clave
            tls!.cert = s.cert
            tls!.nombres = nombres
        }
        if tls!.cert != secretos.tls?.cert {
            secretos.tls = tls
            try Llavero.guardar(secretos)
        }
    }

    /// Un atacante con acceso a tu usuario podría modificar el servidor para usar
    /// el permiso de Accesibilidad de esta app. Por eso se comprueban las huellas.
    private func archivosIntactos() -> Bool {
        for (nombre, esperada) in huellasServidor {
            guard Cripto.sha256(archivo: carpetaServidor.appendingPathComponent(nombre)) == esperada else {
                aviso = "⛔️ El archivo \(nombre) de la app fue modificado. No se encenderá el panel. Reinstala la app con compilar.sh."
                return false
            }
        }
        return true
    }

    /// Se llama cada pocas horas: si el panel lleva días encendido, renueva el
    /// certificado sin esperar a que alguien lo reinicie.
    func revisarCertificados() {
        guard encendido, let t = secretos.tls else { return }
        if Certificados.vence(t.cert, enDias: 60) || Certificados.vence(t.caCert, enDias: 60)
            || t.nombres != Certificados.nombresLocales() {
            reiniciar()
        }
    }

    /// /usr/bin/python3 es un intermediario: el Python real viene con las
    /// herramientas de línea de comandos de Apple (o con Xcode). Se comprueba
    /// sin ejecutarlo, porque si faltan, macOS abriría un instalador.
    private func pythonDisponible() -> Bool {
        let (st, ruta) = correr("/usr/bin/xcode-select", ["-p"])
        let dir = ruta.trimmingCharacters(in: .whitespacesAndNewlines)
        return st == 0 && FileManager.default.isExecutableFile(atPath: dir + "/usr/bin/python3")
    }

    func encender() {
        guard proceso == nil else { return }
        guard archivosIntactos() else { return }
        guard pythonDisponible() else {
            aviso = "Falta Python de Apple (herramientas de línea de comandos). Abre Terminal, ejecuta  xcode-select --install  y vuelve a encender el panel."
            return
        }
        do {
            try prepararCertificados()
        } catch {
            aviso = "No se pudo preparar el certificado: \(error.localizedDescription)"
            return
        }
        token = Cripto.hex(32)
        ultimo = 0
        eventos = []  // el registro solo vive mientras el panel está en uso

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        // -I: ignora variables PYTHON* y carpetas del usuario; -B: no escribe .pyc
        p.arguments = ["-I", "-B", carpetaServidor.appendingPathComponent("server.py").path]
        p.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                         "HOME": NSHomeDirectory(), "LANG": "es_ES.UTF-8"]
        let entrada = Pipe()
        p.standardInput = entrada
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { terminado in
            Task { @MainActor in
                let panel = Panel.shared
                guard panel.proceso === terminado else { return }
                panel.proceso = nil
                panel.encendido = false
                panel.estado = nil
                if panel.reiniciando {
                    panel.reiniciando = false
                    panel.encender()
                } else if terminado.terminationStatus != 0 && terminado.terminationReason == .exit {
                    panel.aviso = "El panel se detuvo: ¿otro programa usa los puertos 8787–8789?"
                }
            }
        }
        do {
            try p.run()
            entrada.fileHandleForWriting.write(try datosParaServidor())
            try entrada.fileHandleForWriting.close()
            proceso = p
            encendido = true
            aviso = nil
        } catch {
            p.terminate()
            aviso = "No se pudo encender: \(error.localizedDescription)"
        }
    }

    private func listaParaServidor() -> [[String: String]] {
        secretos.dispositivos.map { ["id": $0.id, "nombre": $0.nombre, "clave": $0.clave] }
    }

    private func datosParaServidor() throws -> Data {
        var obj: [String: Any] = ["admin_token": token, "dispositivos": listaParaServidor()]
        if let t = secretos.tls { obj["tls"] = ["cert_pem": t.cert, "key_pem": t.clave, "ca_pem": t.caCert] }
        return try JSONSerialization.data(withJSONObject: obj)
    }

    func apagar() { proceso?.terminate() }

    func reiniciar() {
        if proceso == nil { return encender() }
        reiniciando = true
        proceso?.terminate()
    }

    func apagarYEsperar() {
        guard let p = proceso else { return }
        p.terminate()
        p.waitUntilExit()
    }

    func actualizar() async {
        permisoApp = AXIsProcessTrusted()
        guard encendido else { return }
        if let d = try? await pedir("GET", "/estado"), let e = try? JSONDecoder().decode(Estado.self, from: d) {
            estado = e
        }
        if let d = try? await pedir("GET", "/log?desde=\(ultimo)"), let l = try? JSONDecoder().decode(Eventos.self, from: d) {
            eventos.append(contentsOf: l.eventos)
            if eventos.count > 1000 { eventos.removeFirst(eventos.count - 1000) }
            ultimo = l.ultimo
        }
    }

    // MARK: Operaciones con claves (todas piden Touch ID o la contraseña de la Mac)

    private func autenticar(_ motivo: String) async -> Bool {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            aviso = "Esta Mac no tiene contraseña de usuario: no se pueden proteger las claves"
            return false
        }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: motivo)) ?? false
    }

    private func revelado(_ d: DispositivoGuardado) -> Revelado {
        let host = estado?.ip ?? "IP-de-la-Mac"
        return Revelado(nombre: d.nombre, clave: d.clave, url: "https://\(host):8787/#clave=\(d.clave)")
    }

    private func guardarYEnviar() async {
        do {
            try Llavero.guardar(secretos)
        } catch {
            aviso = "No se pudo guardar en el Llavero: \(error.localizedDescription)"
        }
        if encendido {
            _ = try? await pedir("POST", "/dispositivos", cuerpo: ["dispositivos": listaParaServidor()])
            await actualizar()
        }
    }

    func crearConexion(nombre: String) async -> Revelado? {
        guard await autenticar("crear una conexión nueva") else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let limpio = String(nombre.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        let d = DispositivoGuardado(id: Cripto.hex(3), nombre: limpio.isEmpty ? "Dispositivo" : limpio,
                                    clave: Cripto.nuevaClave(), creado: f.string(from: Date()))
        secretos.dispositivos.append(d)
        await guardarYEnviar()
        return revelado(d)
    }

    func mostrarCodigo(_ id: String) async -> Revelado? {
        guard let d = secretos.dispositivos.first(where: { $0.id == id }),
              await autenticar("mostrar la clave de «\(d.nombre)»") else { return nil }
        return revelado(d)
    }

    func nuevaClave(_ id: String) async -> Revelado? {
        guard let i = secretos.dispositivos.firstIndex(where: { $0.id == id }),
              await autenticar("cambiar la clave de «\(secretos.dispositivos[i].nombre)»") else { return nil }
        secretos.dispositivos[i].clave = Cripto.nuevaClave()
        await guardarYEnviar()
        return revelado(secretos.dispositivos[i])
    }

    func revocar(_ id: String) async {
        secretos.dispositivos.removeAll { $0.id == id }
        await guardarYEnviar()
    }

    func nuevoCertificado() async {
        guard await autenticar("crear un certificado nuevo") else { return }
        secretos.tls = nil
        reiniciar()
    }

    func limpiarRegistro() { eventos = [] }

    private func pedir(_ metodo: String, _ ruta: String, cuerpo: [String: Any]? = nil) async throws -> Data {
        var r = URLRequest(url: URL(string: admin + ruta)!)
        r.httpMethod = metodo
        r.timeoutInterval = 5
        r.setValue(token, forHTTPHeaderField: "X-Admin")
        if let cuerpo {
            r.httpBody = try JSONSerialization.data(withJSONObject: cuerpo)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (datos, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return datos
    }
}

// MARK: - Vistas

struct VentanaPrincipal: View {
    @ObservedObject var panel = Panel.shared
    @State private var pidiendoNombre = false
    @State private var mostrar: Revelado?
    @State private var porRevocar: EstadoDispositivo?
    @State private var confirmarCertificado = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                cabecera
                permiso
                botones
                dispositivos
                certificado
                registro
            }
            .padding(20)
        }
        .frame(minWidth: 620, minHeight: 700)
        .sheet(isPresented: $pidiendoNombre) {
            PedirNombre { nombre in
                Task { mostrar = await panel.crearConexion(nombre: nombre) }
            }
        }
        .sheet(item: $mostrar) { r in VerCodigo(revelado: r) }
        .confirmationDialog("¿Revocar la conexión de «\(porRevocar?.nombre ?? "")»?",
                            isPresented: Binding(get: { porRevocar != nil }, set: { if !$0 { porRevocar = nil } }),
                            presenting: porRevocar) { d in
            Button("Revocar", role: .destructive) { Task { await panel.revocar(d.id) } }
        } message: { _ in
            Text("Ese dispositivo dejará de poder controlar la Mac al instante.")
        }
        .confirmationDialog("¿Crear un certificado nuevo?", isPresented: $confirmarCertificado) {
            Button("Crear certificado nuevo", role: .destructive) { Task { await panel.nuevoCertificado() } }
        } message: {
            Text("Todos los dispositivos tendrán que instalar el certificado otra vez. Úsalo solo si crees que el actual se vio comprometido.")
        }
    }

    private var cabecera: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle().fill(panel.encendido ? Color.green : Color.secondary.opacity(0.4)).frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(panel.encendido ? "Encendido" : "Apagado").font(.title2.bold())
                    if panel.estado?.tls == true {
                        Label("HTTPS", systemImage: "lock.fill").font(.caption.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: Capsule()).foregroundStyle(.green)
                    }
                }
                if let e = panel.estado {
                    Text("https://\(e.ip):\(String(e.puerto))").font(.callout.monospaced())
                        .foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let aviso = panel.aviso {
                    Text(aviso).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { panel.encendido }, set: { $0 ? panel.encender() : panel.apagar() }))
                .toggleStyle(.switch).labelsHidden().controlSize(.large)
        }
    }

    @ViewBuilder private var permiso: some View {
        if panel.permisoApp {
            Label("Permiso de Accesibilidad activo", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
        } else {
            HStack {
                Label("Falta el permiso de Accesibilidad: las teclas no funcionarán",
                      systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Spacer()
                Button("Abrir Ajustes") {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        }
    }

    private var botones: some View {
        HStack {
            Button { panel.reiniciar() } label: { Label("Reiniciar", systemImage: "arrow.clockwise") }
            Button { pidiendoNombre = true } label: { Label("Nueva conexión…", systemImage: "plus.circle") }
                .disabled(!panel.encendido)
            Spacer()
        }
        .controlSize(.large)
    }

    private var dispositivos: some View {
        GroupBox("Dispositivos") {
            let lista = panel.estado?.dispositivos ?? []
            if lista.isEmpty {
                Text(panel.encendido ? "Ninguno todavía. Usa «Nueva conexión…»." : "Enciende el panel para ver los dispositivos.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(6)
            } else {
                VStack(spacing: 0) {
                    ForEach(lista) { d in
                        HStack(spacing: 10) {
                            Circle().fill(d.conectado ? Color.green : Color.secondary.opacity(0.4)).frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.nombre).font(.body.weight(.medium))
                                Text(detalle(d)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Mostrar código") { Task { mostrar = await panel.mostrarCodigo(d.id) } }
                            Button("Nueva clave") { Task { mostrar = await panel.nuevaClave(d.id) } }
                            Button("Revocar", role: .destructive) { porRevocar = d }.foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .padding(.vertical, 6).padding(.horizontal, 4)
                        if d.id != lista.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func detalle(_ d: EstadoDispositivo) -> String {
        guard let hace = d.visto_hace else { return "Sin conectarse desde que se encendió el panel" }
        let cuando = hace < 60 ? "hace \(Int(hace)) s" : "hace \(Int(hace / 60)) min"
        return (d.conectado ? "Conectado" : "Desconectado") + " · \(d.ip ?? "") · última actividad \(cuando)"
    }

    private var certificado: some View {
        GroupBox("Certificado HTTPS") {
            VStack(alignment: .leading, spacing: 6) {
                if let e = panel.estado {
                    Text("Para instalarlo en un dispositivo, abre en su Safari:  http://\(e.ip):\(String(e.puerto_cert))")
                        .textSelection(.enabled)
                }
                Text("Huella SHA-256 de la CA (debe coincidir con la que muestre el dispositivo):")
                    .font(.caption).foregroundStyle(.secondary)
                Text(panel.huellaCA).font(.caption2.monospaced()).textSelection(.enabled)
                if let a = panel.avisoCA {
                    Label(a, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                HStack {
                    Spacer()
                    Button("Crear certificado nuevo…") { confirmarCertificado = true }.buttonStyle(.borderless)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(4)
        }
    }

    private var registro: some View {
        GroupBox {
            ScrollViewReader { lector in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(panel.eventos) { e in
                            Text("\(e.hora)  \(e.texto)").font(.caption.monospaced()).textSelection(.enabled).id(e.seq)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
                .onChange(of: panel.eventos.count) { _, _ in
                    if let ultimo = panel.eventos.last { lector.scrollTo(ultimo.seq, anchor: .bottom) }
                }
            }
            .frame(minHeight: 150, maxHeight: 220)
        } label: {
            HStack {
                Text("Registro")
                Text("· se borra al apagar o cerrar la app").foregroundStyle(.secondary)
                Spacer()
                Button("Limpiar") { panel.limpiarRegistro() }.buttonStyle(.borderless)
            }
        }
    }
}

struct PedirNombre: View {
    let crear: (String) -> Void
    @Environment(\.dismiss) private var cerrar
    @State private var nombre = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Nueva conexión").font(.title2.bold())
            TextField("Nombre del dispositivo (ej. iPad Air)", text: $nombre)
                .textFieldStyle(.roundedBorder).frame(width: 320)
                .onSubmit { listo() }
            Text("Se te pedirá Touch ID o la contraseña de la Mac.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancelar") { cerrar() }.keyboardShortcut(.cancelAction)
                Button("Crear conexión") { listo() }.keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(28)
    }

    private func listo() {
        cerrar()
        crear(nombre)
    }
}

struct VerCodigo: View {
    let revelado: Revelado
    @ObservedObject var panel = Panel.shared
    @Environment(\.dismiss) private var cerrar
    @State private var quedan = 120

    var body: some View {
        VStack(spacing: 14) {
            Text("Emparejar «\(revelado.nombre)»").font(.title2.bold())
            if let e = panel.estado {
                Text("1. Si es la primera vez, instala el certificado: en el dispositivo abre  http://\(e.ip):\(String(e.puerto_cert))")
                    .font(.callout).multilineTextAlignment(.center).textSelection(.enabled)
            }
            Text("2. Escanea este código con la cámara del dispositivo:").font(.callout)
            Image(nsImage: codigoQR(revelado.url)).interpolation(.none).resizable()
                .frame(width: 230, height: 230).background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(spacing: 4) {
                Text("O escribe esta clave en la página del panel:").font(.callout).foregroundStyle(.secondary)
                Text(revelado.clave).font(.system(size: 22, weight: .semibold, design: .monospaced)).textSelection(.enabled)
            }
            Text("No compartas esta pantalla. Se cerrará sola en \(quedan) s.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Listo") { cerrar() }.keyboardShortcut(.defaultAction).controlSize(.large)
        }
        .padding(28)
        .frame(width: 480)
        .task {
            while quedan > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                quedan -= 1
            }
            cerrar()
        }
    }

    private func codigoQR(_ texto: String) -> NSImage {
        let filtro = CIFilter.qrCodeGenerator()
        filtro.message = Data(texto.utf8)
        filtro.correctionLevel = "M"
        guard let salida = filtro.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return NSImage() }
        let rep = NSCIImageRep(ciImage: salida)
        let imagen = NSImage(size: rep.size)
        imagen.addRepresentation(rep)
        return imagen
    }
}

struct MenuBarra: View {
    @ObservedObject var panel = Panel.shared
    @Environment(\.openWindow) private var abrirVentana

    var body: some View {
        Text(panel.encendido ? "Panel encendido" : "Panel apagado")
        Button(panel.encendido ? "Apagar" : "Encender") { panel.encendido ? panel.apagar() : panel.encender() }
        Button("Reiniciar") { panel.reiniciar() }
        Divider()
        Button("Abrir ventana") {
            abrirVentana(id: "principal")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Salir") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

// MARK: - App

final class Delegado: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { Panel.shared.apagarYEsperar() }
    }
}

@main
struct PanelDeAtajos: App {
    @NSApplicationDelegateAdaptor(Delegado.self) var delegado
    @ObservedObject var panel = Panel.shared

    var body: some Scene {
        Window("Panel de atajos", id: "principal") { VentanaPrincipal() }
            .windowResizability(.contentMinSize)
        MenuBarExtra {
            MenuBarra()
        } label: {
            Image(systemName: panel.encendido ? "keyboard.fill" : "keyboard")
        }
    }
}
