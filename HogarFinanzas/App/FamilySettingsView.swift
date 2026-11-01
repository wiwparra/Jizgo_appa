import SwiftUI
import HogarCore

struct FamilySettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var url = ""
    @State private var key = ""
    @State private var email = ""
    @State private var password = ""
    @State private var newPassword = ""
    @State private var repeatedPassword = ""
    @State private var displayName = ""
    @State private var homeName = "Mi familia"
    @State private var invitationEmail = ""
    @State private var invitationCode = ""
    @State private var busy = false
    @State private var removing: Member?
    @State private var leaving = false
    @State private var copying = false
    @State private var resolving = false
    @State private var signingOut = false
    @State private var recovering = false
    var body: some View {
        Form {
            InlineSaveError()
            if let notice = store.familyNotice { Section { Text(notice) } }
            if store.demo {
                Section { Text("Sal del modo de demostración en Hogar y copias antes de conectar un hogar real.") }
            } else if store.familySession == nil { loginSections }
            else {
                sessionSection
                passwordSection
                conflictSection
                archiveSections
                if store.familyEnabled {
                    homeSection
                    if store.familyIsAdmin { invitationSection; copySection }
                } else { homeChoiceSections }
            }
        }.formStyle(.grouped).navigationTitle("Acceso familiar").disabled(busy)
        .overlay { if busy { ProgressView("Conectando…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .task {
            if url.isEmpty { url = store.familyConfiguration?.url.absoluteString ?? ""; key = store.familyConfiguration?.publicKey ?? "" }
            if store.familySession != nil { await store.refreshFamilyHomes(); await store.refreshInvitations() }
        }
        .confirmationDialog("¿Revocar el acceso de este miembro?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Revocar acceso", role: .destructive) { if let member = removing { run { await store.changeMembership(member, role: member.role, active: false) } }; removing = nil }
        }
        .confirmationDialog("¿Salir del hogar? Los datos locales previos y copias no se borrarán.", isPresented: $leaving, titleVisibility: .visible) {
            Button("Salir del hogar", role: .destructive) { if let member = store.household?.members.first(where: { $0.id == store.familySession?.user.id }) { run { await store.changeMembership(member, role: member.role, active: false) } } }
        }
        .confirmationDialog("¿Copiar el hogar local al hogar compartido vacío? Se enviarán sus datos financieros al servicio configurado.", isPresented: $copying, titleVisibility: .visible) {
            Button("Copiar y sincronizar") { store.copyLocalToFamily() }
        }
        .confirmationDialog("¿Conservar una copia local y cargar el estado compartido? Los cambios pendientes no se enviarán automáticamente después.", isPresented: $resolving, titleVisibility: .visible) {
            Button("Archivar y cargar compartidos") { store.resolveFamilyConflict() }
        }
        .confirmationDialog("¿Conservar el archivo ilegible y cargar los datos del servidor? Los cambios no enviados pueden necesitar recuperación manual.", isPresented: $recovering, titleVisibility: .visible) {
            Button("Conservar original y descargar") { run { await store.recoverFamilyCache() } }
        }
        .confirmationDialog("¿Cerrar sesión? Los cambios pendientes se conservan en este dispositivo y podrás retomarlos al entrar con la misma cuenta.", isPresented: $signingOut, titleVisibility: .visible) {
            Button("Cerrar sesión", role: .destructive) { run { await store.familySignOut() } }
        }
    }

    @ViewBuilder private var loginSections: some View {
        Section("Configurar servicio") {
            Text("Usa el proyecto Supabase que hayas preparado con el esquema de esta app. No necesitas Apple Developer de pago. Consulta Supabase/LEEME.md del proyecto descargado.").font(.callout)
            TextField("URL https://…supabase.co", text: $url)
            TextField("Clave pública publishable o anon", text: $key)
            Text("Nunca uses una clave secret o service_role. La clave pública identifica el proyecto; los permisos se comprueban en el servidor.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Tu cuenta personal") {
            TextField("Correo", text: $email)
            SecureField("Contraseña", text: $password)
            Button("Iniciar sesión") { run { await store.familySignIn(url: url, key: key, email: email, password: password); password = "" } }.disabled(email.isEmpty || password.isEmpty)
            Button("Crear cuenta") { run { await store.familySignUp(url: url, key: key, email: email, password: password); password = "" } }.disabled(email.isEmpty || password.count < 12)
            Text("Cada familiar usa su propia cuenta con correo confirmado. Si no se configuró envío de correo en el servicio, pide al administrador que cree tu cuenta desde su panel, en lugar de usar Crear cuenta. No se usa un selector de nombres para acceder como otra persona.").font(.caption)
        }
    }
    @ViewBuilder private var sessionSection: some View {
        Section("Sesión") {
            Text(store.familySession?.user.email ?? "Cuenta conectada")
            Text(store.familyEnabled ? store.syncStatus.label : "Modo local · sesión familiar disponible").font(.callout)
            if let workspace = store.familyWorkspace {
                Text("\(workspace.outbox.count) cambios pendientes").font(.caption)
                if workspace.accessRevoked { Label("Acceso revocado. No se enviarán cambios.", systemImage: "lock.fill").foregroundStyle(.orange) }
            }
            if store.familyEnabled {
                if store.readFailed { Button("Conservar archivo ilegible y descargar hogar") { recovering = true } }
                Button("Sincronizar ahora") { run { await store.synchronizeFamily() } }
                Button("Volver a mis datos locales") { store.returnToLocal() }
            }
            Button("Cerrar sesión en este dispositivo", role: .destructive) { signingOut = true }
        }
    }
    @ViewBuilder private var passwordSection: some View {
        Section("Contraseña personal") {
            SecureField("Nueva contraseña (12 caracteres o más)", text: $newPassword)
            SecureField("Repetir contraseña", text: $repeatedPassword)
            Button("Cambiar mi contraseña") { run { await store.changeFamilyPassword(newPassword); newPassword = ""; repeatedPassword = "" } }.disabled(newPassword.count < 12 || newPassword != repeatedPassword)
        }
    }
    @ViewBuilder private var conflictSection: some View {
        if let remote = store.familyConflict, let workspace = store.familyWorkspace {
            Section("Revisar conflicto") {
                Text("El servidor no ha aceptado la propuesta. Tus \(workspace.outbox.count) cambios pendientes se conservan; no se han sobrescrito los datos del servidor.")
                LabeledContent("Movimientos locales", value: "\(workspace.visible.entries.filter { !$0.deleted }.count)")
                LabeledContent("Movimientos compartidos", value: "\(remote.household.entries.filter { !$0.deleted }.count)")
                let remoteEntries = Dictionary(uniqueKeysWithValues: remote.household.entries.map { ($0.id, $0) })
                ForEach(workspace.visible.entries.filter { remoteEntries[$0.id] != $0 }) { entry in
                    Text("Cambio local: \(entry.title) · \(entry.amount.formatted)\(entry.deleted ? " · eliminado" : "")").font(.caption)
                }
                Text("También se conservarán en la copia las cuentas, presupuestos y metas locales. Después podrás recuperar los cambios que falten sin forzar una sobrescritura del hogar.").font(.caption)
                Button("Archivar mis cambios y cargar los compartidos") { resolving = true }
            }
        }
    }
    @ViewBuilder private var archiveSections: some View {
        if let archive = store.familyRecoveryArchiveURL {
            Section("Archivo original conservado") {
                ShareLink("Guardar archivo ilegible", item: archive)
                Text("Contiene datos financieros y puede necesitar recuperación manual. No es una copia validada.").font(.caption)
            }
        }
        if let archive = store.familyArchiveURL {
            Section("Copia conservada") {
                ShareLink("Guardar copia de los cambios locales", item: archive)
                Text("Contiene finanzas en claro. Guárdala en una ubicación privada. Puedes restaurarla en modo local para revisarla.").font(.caption)
            }
        }
    }
    @ViewBuilder private var homeSection: some View {
        Section("Hogar compartido") {
            Text(store.household?.name ?? "Hogar").font(.headline)
            ForEach(store.household?.members ?? []) { member in
                HStack {
                    VStack(alignment: .leading) {
                        Text(member.name)
                        Text(!member.active ? "Acceso revocado" : member.role == .admin ? "Administrador" : "Miembro").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.familyIsAdmin && member.active {
                        Menu("Gestionar") {
                            Button(member.role == .admin ? "Cambiar a miembro" : "Hacer administrador") { run { await store.changeMembership(member, role: member.role == .admin ? .member : .admin, active: true) } }
                            if member.id != store.familySession?.user.id { Button("Revocar acceso", role: .destructive) { removing = member } }
                        }
                    }
                }
            }
            Button("Salir del hogar", role: .destructive) { leaving = true }
            Text("Revocar acceso bloquea las lecturas y escrituras remotas. No puede borrar archivos o copias que una persona ya descargó.").font(.caption)
        }
    }
    @ViewBuilder private var invitationSection: some View {
        Section("Invitar familiar") {
            TextField("Correo confirmado del familiar", text: $invitationEmail)
            Button("Crear invitación") { run { await store.createInvitation(email: invitationEmail) } }.disabled(invitationEmail.isEmpty)
            if let invitation = store.familyInvitation, let code = invitation.token {
                Text("Invitación para \(invitation.email)")
                Text(code).font(.caption.monospaced()).textSelection(.enabled)
                ShareLink(item: code, subject: Text("Invitación a Hogar Finanzas"), message: Text("Inicia sesión con \(invitation.email) en Hogar Finanzas y pega este código en Aceptar invitación. Válido hasta \(Date(timeIntervalSince1970: invitation.expiresAt).formatted(date: .abbreviated, time: .shortened)).")) { Label("Compartir código", systemImage: "square.and.arrow.up") }
            }
            ForEach(store.familyInvitations) { invitation in
                HStack {
                    Text(invitation.email).font(.caption)
                    Spacer()
                    Button("Anular", role: .destructive) { run { await store.cancelInvitation(invitation) } }
                }
            }
        }
    }
    @ViewBuilder private var copySection: some View {
        if store.household?.accounts.isEmpty == true && store.familyWorkspace?.outbox.isEmpty == true {
            Section {
                Button("Copiar mi hogar local a este hogar vacío") { copying = true }
                Text("La copia local se conserva. Los autores antiguos quedan sin verificar y las atribuciones previas se conservan en notas; no se convierten nombres locales en cuentas familiares.").font(.caption)
            }
        }
    }
    @ViewBuilder private var homeChoiceSections: some View {
        Section("Mis hogares") {
            ForEach(store.familyHomes) { home in Button(home.name) { run { await store.openFamily(home.id) } } }
            Button("Actualizar lista") { run { await store.refreshFamilyHomes() } }
        }
        Section("Crear hogar familiar nuevo") {
            TextField("Tu nombre visible", text: $displayName)
            TextField("Nombre del hogar", text: $homeName)
            Button("Crear hogar compartido") { run { await store.createFamily(name: homeName, displayName: displayName) } }.disabled(displayName.isEmpty || homeName.isEmpty)
        }
        Section("Aceptar invitación") {
            TextField("Tu nombre visible", text: $displayName)
            TextField("Código de invitación", text: $invitationCode, axis: .vertical)
            Button("Aceptar y abrir hogar") { run { await store.acceptFamily(code: invitationCode, displayName: displayName) } }.disabled(displayName.isEmpty || invitationCode.isEmpty)
            Text("La invitación está ligada al correo de tu cuenta y caduca en siete días. Todos deben configurar el mismo proyecto Supabase.").font(.caption)
        }
    }
    private func run(_ action: @escaping @MainActor () async -> Void) {
        guard !busy else { return }
        busy = true
        Task { await action(); busy = false }
    }
}
