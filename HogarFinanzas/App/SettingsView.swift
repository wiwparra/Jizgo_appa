import SwiftUI
import UniformTypeIdentifiers
import HogarCore

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var importing = false
    @State private var exporting = false
    @State private var document: BackupDocument?
    @State private var pendingRestore: Data?
    @State private var restoredName = ""
    @State private var confirmation = false
    var body: some View {
        Form {
            Section("Hogar") {
                Text(store.household?.name ?? "Sin hogar cargado").font(.headline)
                ForEach(store.household?.members ?? []) { member in
                    LabeledContent(member.name, value: member.role == .admin ? "Administrador local" : "Miembro")
                }
                Text("La identidad local no es una autenticación iCloud. No hay selector para acceder como otra persona.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Colaboración familiar · pendiente") {
                Label("Acceso familiar no disponible", systemImage: "person.2.slash")
                Text("Esta entrega no envía invitaciones ni sincroniza dispositivos. Se necesita implementar una autoridad que autentique usuarios y aplique permisos por autor, además de validar dos cuentas iCloud independientes.")
                Text("No basta con activar un contenedor iCloud. Consulta docs/ICLOUD.md antes de habilitar la colaboración.").font(.caption)
            }
            Section("Copias de seguridad") {
                Text("También puedes importar copias del prototipo 0.1. Las copias JSON contienen los datos financieros en claro. Guárdalas en una ubicación protegida. Restaurar reemplaza por completo el hogar de este modo.").font(.callout)
                Button("Exportar copia") {
                    do { document = BackupDocument(data: try store.exportData()); exporting = true }
                    catch { store.error = error.localizedDescription }
                }.disabled(store.household == nil)
                Button("Seleccionar copia para restaurar") { importing = true }
            }
            Section("Demostración") {
                Toggle("Usar datos de demostración separados", isOn: Binding(get: { store.demo }, set: { store.setDemo($0) }))
                Text("Los archivos de demostración y los reales se guardan por separado. Desactivar este modo recupera los datos reales.").font(.caption)
            }
            Section("Acerca de tus cifras") {
                Text("El saldo registrado incluye todos los movimientos, también los fechados en el futuro. Los informes mensuales usan el calendario de Madrid. Las reservas no descuentan compromisos futuros ni garantizan liquidez por cuenta.")
                Text("Almacenamiento local atómico. Protección de archivo completa en iOS y permisos de archivo en macOS. No se ha implementado cifrado propio ni protección por contraseña de copias.").font(.caption)
            }
        }.formStyle(.grouped).navigationTitle("Hogar y copias")
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: store.demo ? "hogar-demo" : "hogar-finanzas") { result in
            if case .failure(let error) = result { store.error = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 64 * 1024 * 1024 else { throw FinanceError.corrupt }
                let data = try Data(contentsOf: url)
                let home: Household
                let normalized: Data
                let warning: String
                if let native = try? Backup.decode(data) {
                    home = native; normalized = data; warning = ""
                } else {
                    let migration = try LegacyImport(data: data, budgetMonth: Month(Date()))
                    home = migration.household
                    normalized = try Backup(household: home).encoded()
                    warning = " " + migration.warnings
                }
                restoredName = "\(home.name): \(home.accounts.count) cuentas, \(home.entries.filter { !$0.deleted }.count) movimientos." + warning
                pendingRestore = normalized; confirmation = true
            } catch { store.error = error.localizedDescription }
        }
        .confirmationDialog("¿Reemplazar los datos actuales?", isPresented: $confirmation, titleVisibility: .visible) {
            Button("Reemplazar con esta copia", role: .destructive) {
                if let pendingRestore { store.restore(pendingRestore) }
                pendingRestore = nil
            }
            Button("Cancelar", role: .cancel) { pendingRestore = nil }
        } message: { Text(restoredName + " Exporta antes los datos actuales si quieres conservarlos.") }
    }
}
