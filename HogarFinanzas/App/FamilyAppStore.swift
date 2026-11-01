import Foundation
import HogarCore

@MainActor
extension AppStore {
    var familyIsAdmin: Bool { familyEnabled && canManageHousehold }
    private var selectionKey: String? {
        guard let host = familyConfiguration?.url.host, let user = familySession?.user.id else { return nil }
        return "family.home." + host + "." + user.uuidString
    }
    private func workspaceURL(home: UUID) throws -> URL {
        guard let host = familyConfiguration?.url.host, let user = familySession?.user.id else { throw FamilyRemoteError.authentication }
        return root.appendingPathComponent("familia-" + host, isDirectory: true).appendingPathComponent(user.uuidString + "-" + home.uuidString + ".json")
    }
    func resumeFamily() {
        do {
            guard let data = UserDefaults.standard.data(forKey: "family.configuration") else { return }
            let config = try JSONDecoder().decode(SupabaseConfiguration.self, from: data).validated()
            familyConfiguration = config
            familySession = try FamilyCredentials.load(host: config.url.host!)
            if UserDefaults.standard.bool(forKey: "family.enabled"), familySession != nil, let selectionKey,
               let text = UserDefaults.standard.string(forKey: selectionKey), let home = UUID(uuidString: text) {
                familyEnabled = true
                household = nil
                familyRepository = FamilyWorkspaceRepository(url: try workspaceURL(home: home))
                reloadFamilyFromDisk()
            }
        } catch { self.error = "No se ha podido recuperar la sesión familiar. Tus archivos se conservan; desbloquea el dispositivo o vuelve a iniciar sesión." }
    }
    func reloadFamilyFromDisk() {
        do {
            guard let repository = familyRepository, let cached = try repository.load(), cached.userID == familySession?.user.id else { throw FinanceError.corrupt }
            guard let selectionKey, UUID(uuidString: UserDefaults.standard.string(forKey: selectionKey) ?? "") == cached.server.household.id else { throw FinanceError.corrupt }
            familyWorkspace = cached; household = cached.visible; readFailed = false
            syncStatus = cached.accessRevoked ? .error("Acceso revocado") : .pending
        } catch { readFailed = true; self.error = "No se pudo leer el hogar familiar. El archivo y los cambios pendientes se conservan. Puedes volver al modo local o iniciar sesión de nuevo; no se creará un hogar vacío." }
    }
    func familySignIn(url: String, key: String, email: String, password: String) async {
        guard !demo else { error = "Sal del modo de demostración antes de conectar una cuenta real."; return }
        guard familySession == nil else { error = "Cierra la sesión actual antes de cambiar de cuenta o proyecto."; return }
        do {
            let config = try SupabaseConfiguration(url: url, publicKey: key)
            let session = try await SupabaseClient(configuration: config).signIn(email: email, password: password)
            try FamilyCredentials.save(session, host: config.url.host!)
            UserDefaults.standard.set(try JSONEncoder().encode(config), forKey: "family.configuration")
            familyConfiguration = config; familySession = session; familyGeneration = UUID(); familyAuthGeneration = UUID(); familyRefreshTask = nil
            await refreshFamilyHomes()
        } catch { reportFamily(error) }
    }
    func familySignUp(url: String, key: String, email: String, password: String) async {
        do {
            guard !demo else { throw FinanceError.invalid("Sal del modo de demostración antes de usar una cuenta real.") }
            let config = try SupabaseConfiguration(url: url, publicKey: key)
            try await SupabaseClient(configuration: config).signUp(email: email, password: password)
            familyNotice = "Revisa tu correo y confirma la dirección. Después vuelve aquí e inicia sesión. Si no llega, revisa la configuración de correo y sus límites en Supabase."
        } catch { reportFamily(error) }
    }
    private func renewedFamilySession(_ old: FamilySession, client: SupabaseClient) async throws -> FamilySession {
        guard let current = familySession, current.user.id == old.user.id, let host = familyConfiguration?.url.host else { throw FamilyRemoteError.authentication }
        if current.accessToken != old.accessToken && !current.requiresRefresh { return current }
        let authGeneration = familyAuthGeneration
        let task: Task<FamilySession, Error>
        let requestID: UUID
        if let existing = familyRefreshTask { task = existing; requestID = familyRefreshID }
        else {
            requestID = UUID(); familyRefreshID = requestID
            task = Task { try await client.refresh(current) }
            familyRefreshTask = task
        }
        defer { if authGeneration == familyAuthGeneration && familyRefreshID == requestID { familyRefreshTask = nil } }
        let refreshed = try await task.value
        guard authGeneration == familyAuthGeneration, familySession?.user.id == refreshed.user.id else { throw FamilyRemoteError.authentication }
        if familyRefreshID != requestID, let latest = familySession, latest.accessToken != refreshed.accessToken { return latest }
        try FamilyCredentials.save(refreshed, host: host)
        familySession = refreshed
        return refreshed
    }
    func authorizedFamily<T>(_ call: (SupabaseClient, String) async throws -> T) async throws -> T {
        guard let config = familyConfiguration, var session = familySession else { throw FamilyRemoteError.authentication }
        let generation = familyGeneration
        let client = try SupabaseClient(configuration: config)
        if session.requiresRefresh { session = try await renewedFamilySession(session, client: client) }
        let result: T
        do { result = try await call(client, session.accessToken) }
        catch FamilyRemoteError.authentication {
            let refreshed = try await renewedFamilySession(session, client: client)
            result = try await call(client, refreshed.accessToken)
        }
        guard generation == familyGeneration else { throw FamilyRemoteError.authentication }
        return result
    }
    func refreshFamilyHomes() async {
        do {
            let generation = familyGeneration
            let homes = try await authorizedFamily { client, token in try await client.list(token: token) }
            guard generation == familyGeneration else { return }
            familyHomes = homes
        } catch { reportFamily(error) }
    }
    private func activateFamily(_ snapshot: FamilySnapshot) throws {
        guard !demo, let user = familySession?.user.id else { throw FamilyRemoteError.authentication }
        try snapshot.validate(); _ = try snapshot.household.authorized(user)
        let storage = FamilyWorkspaceRepository(url: try workspaceURL(home: snapshot.household.id))
        var workspace: FamilyWorkspace
        let cached: FamilyWorkspace?
        do { cached = try storage.load() }
        catch {
            // La selección está autorizada, pero su caché no se puede leer. No se sobrescribe al abrir.
            familyGeneration = UUID(); familySyncRunning = false
            familyRepository = storage; familyWorkspace = nil; household = nil
            familyEnabled = true; readFailed = true; syncStatus = .error("Caché ilegible")
            if let selectionKey { UserDefaults.standard.set(snapshot.household.id.uuidString, forKey: selectionKey) }
            UserDefaults.standard.set(true, forKey: "family.enabled")
            throw FinanceError.corrupt
        }
        if let cached {
            guard cached.userID == user, cached.server.household.id == snapshot.household.id else { throw FinanceError.forbidden }
            workspace = cached
            if workspace.outbox.isEmpty { try workspace.receive(snapshot) }
            else if workspace.server.revision != snapshot.revision || workspace.accessRevoked { familyConflict = snapshot }
        } else { workspace = try FamilyWorkspace(userID: user, server: snapshot) }
        try storage.save(workspace)
        familyGeneration = UUID(); familySyncRunning = false
        familyRepository = storage; familyWorkspace = workspace; household = workspace.visible
        familyEnabled = true; readFailed = false; syncStatus = .pending
        if let selectionKey { UserDefaults.standard.set(snapshot.household.id.uuidString, forKey: selectionKey) }
        UserDefaults.standard.set(true, forKey: "family.enabled")
    }
    func openFamily(_ home: UUID) async {
        do {
            let generation = familyGeneration
            let snapshot = try await authorizedFamily { client, token in try await client.fetch(home: home, token: token) }
            guard generation == familyGeneration else { return }
            try activateFamily(snapshot)
            await synchronizeFamily()
        } catch { reportFamily(error) }
    }
    private struct CreationRequest: Codable { let id: UUID; let name: String; let displayName: String }
    func createFamily(name: String, displayName: String) async {
        do {
            guard let config = familyConfiguration, let user = familySession?.user.id else { throw FamilyRemoteError.authentication }
            let pending = root.appendingPathComponent("creacion-" + config.url.host! + "-" + user.uuidString + ".json")
            let creation: CreationRequest
            if FileManager.default.fileExists(atPath: pending.path) {
                creation = try JSONDecoder().decode(CreationRequest.self, from: Data(contentsOf: pending))
            } else {
                creation = CreationRequest(id: UUID(), name: name, displayName: displayName)
                try ProtectedFile.write(JSONEncoder().encode(creation), to: pending)
            }
            let generation = familyGeneration
            let snapshot = try await authorizedFamily { client, token in try await client.create(name: creation.name, displayName: creation.displayName, id: creation.id, token: token) }
            guard generation == familyGeneration else { return }
            try activateFamily(snapshot)
            try FileManager.default.removeItem(at: pending)
            await refreshFamilyHomes()
            await synchronizeFamily()
        } catch { reportFamily(error) }
    }
    func acceptFamily(code: String, displayName: String) async {
        do {
            let generation = familyGeneration
            let snapshot = try await authorizedFamily { client, token in try await client.accept(code: code, displayName: displayName, token: token) }
            guard generation == familyGeneration else { return }
            try activateFamily(snapshot)
            await refreshFamilyHomes()
            await synchronizeFamily()
        } catch { reportFamily(error) }
    }
    func synchronizeFamily() async {
        guard familyEnabled, !readFailed, !familySyncRunning, familyConflict == nil,
              familyWorkspace?.accessRevoked == false, familySession != nil else { return }
        let generation = familyGeneration
        familySyncRunning = true; syncStatus = .syncing
        defer { if generation == familyGeneration { familySyncRunning = false } }
        do {
            for _ in 0..<101 {
                guard generation == familyGeneration, let workspace = familyWorkspace, let storage = familyRepository else { return }
                if let operation = workspace.outbox.first {
                    let receipt = try await authorizedFamily { client, token in try await client.commit(home: workspace.server.household.id, operation: operation, token: token) }
                    guard generation == familyGeneration, var fresh = familyWorkspace else { return }
                    try fresh.acknowledge(receipt)
                    try storage.save(fresh)
                    familyWorkspace = fresh; household = fresh.visible
                } else {
                    let remote = try await authorizedFamily { client, token in try await client.fetch(home: workspace.server.household.id, token: token) }
                    guard generation == familyGeneration, var fresh = familyWorkspace else { return }
                    // Pueden haberse creado más cambios locales mientras la petición estaba en vuelo.
                    if !fresh.outbox.isEmpty { continue }
                    try fresh.receive(remote); try storage.save(fresh)
                    familyWorkspace = fresh; household = fresh.visible; syncStatus = .synced
                    return
                }
            }
            syncStatus = .pending
        } catch {
            guard generation == familyGeneration else { return }
            if let failure = error as? FamilyRemoteError, [.conflict, .invalidData, .insufficientFunds, .forbidden].contains(failure),
               familyWorkspace?.outbox.isEmpty == false, let home = familyWorkspace?.server.household.id {
                do { familyConflict = try await authorizedFamily { client, token in try await client.fetch(home: home, token: token) } }
                catch { reportFamily(error) }
            }
            if error as? FamilyRemoteError == .accessRevoked, var workspace = familyWorkspace, let storage = familyRepository {
                workspace.revokeAccess()
                do { try storage.save(workspace); familyWorkspace = workspace }
                catch { self.error = "No se ha podido guardar el bloqueo de acceso. Se conserva la cola y no se enviarán más cambios hasta iniciar sesión de nuevo." }
            }
            syncStatus = .error((error as? FamilyRemoteError)?.localizedDescription ?? "Sin conexión. Los datos y cambios pendientes se conservan.")
        }
    }
    func recoverFamilyCache() async {
        do {
            guard familyEnabled, let storage = familyRepository, let user = familySession?.user.id, let selectionKey,
                  let home = UUID(uuidString: UserDefaults.standard.string(forKey: selectionKey) ?? "") else { throw FinanceError.corrupt }
            let snapshot = try await authorizedFamily { client, token in try await client.fetch(home: home, token: token) }
            let (workspace, archive) = try storage.recover(from: snapshot, userID: user, confirmed: true)
            familyWorkspace = workspace; household = workspace.visible; readFailed = false; familyConflict = nil
            familyRecoveryArchiveURL = archive; syncStatus = .synced
            familyNotice = "El archivo ilegible se conservó antes de descargar el hogar. Los cambios que no hubieran llegado al servidor siguen solo en ese archivo, que puede necesitar recuperación manual."
        } catch { reportFamily(error) }
    }
    func copyLocalToFamily() {
        guard familyEnabled, familyIsAdmin, let remote = household, familyWorkspace?.outbox.isEmpty == true else { error = "Sincroniza primero y usa un hogar familiar vacío."; return }
        do {
            let local = LocalRepository(url: root.appendingPathComponent("hogar.json"))
            guard let snapshot = try local.load() else { throw FinanceError.invalid("No hay un hogar local que copiar.") }
            let copied = try FamilyMigration.copyLocal(snapshot, into: remote, actor: familySession!.user.id)
            update { household, _ in household = copied }
        } catch { reportFamily(error) }
    }
    func createInvitation(email: String) async {
        do {
            guard familyIsAdmin, let home = household?.id else { throw FinanceError.forbidden }
            await synchronizeFamily()
            guard familyWorkspace?.outbox.isEmpty == true, familyConflict == nil else { throw FinanceError.conflict }
            familyInvitation = try await authorizedFamily { client, token in try await client.invite(home: home, email: email, token: token) }
            await refreshInvitations()
        } catch { reportFamily(error) }
    }
    func refreshInvitations() async {
        guard familyIsAdmin, let home = household?.id else { return }
        do { familyInvitations = try await authorizedFamily { client, token in try await client.invitations(home: home, token: token) } }
        catch { reportFamily(error) }
    }
    func cancelInvitation(_ invitation: FamilyInvitation) async {
        guard let home = household?.id else { return }
        do {
            try await authorizedFamily { client, token in try await client.cancel(home: home, invite: invitation.id, token: token) }
            if familyInvitation?.id == invitation.id { familyInvitation = nil }
            await refreshInvitations()
        } catch { reportFamily(error) }
    }
    func changeMembership(_ member: Member, role: Role, active: Bool) async {
        do {
            guard let home = household?.id else { throw FamilyRemoteError.authentication }
            await synchronizeFamily()
            guard familyWorkspace?.outbox.isEmpty == true, familyConflict == nil else { throw FinanceError.conflict }
            try await authorizedFamily { client, token in try await client.membership(home: home, user: member.id, role: role, active: active, token: token) }
            if member.id == familySession?.user.id && !active {
                if var workspace = familyWorkspace, let storage = familyRepository { workspace.revokeAccess(); try storage.save(workspace); familyWorkspace = workspace }
                returnToLocal()
            } else { await synchronizeFamily() }
            await refreshFamilyHomes()
        } catch { reportFamily(error) }
    }
    func resolveFamilyConflict() {
        do {
            guard var workspace = familyWorkspace, let remote = familyConflict, let storage = familyRepository else { throw FinanceError.conflict }
            let archived = try storage.archive(workspace)
            let backup = archived.deletingPathExtension().appendingPathExtension("copia.json")
            try ProtectedFile.write(Backup(household: workspace.visible).encoded(), to: backup)
            try workspace.replaceAfterConflict(remote, confirmed: true)
            try storage.save(workspace)
            familyWorkspace = workspace; household = workspace.visible; familyConflict = nil
            familyArchiveURL = backup; familyNotice = "Se conservó una copia de tus cambios locales antes de cargar el hogar compartido. Guárdala para revisar o recuperar lo que falte."
            Task { await synchronizeFamily() }
        } catch { reportFamily(error) }
    }
    func returnToLocal() {
        familyGeneration = UUID(); familySyncRunning = false; familyEnabled = false
        familyWorkspace = nil; familyRepository = nil; familyConflict = nil; familyInvitation = nil; familyInvitations = []
        UserDefaults.standard.set(false, forKey: "family.enabled")
        syncStatus = .localOnly; readFailed = false; household = nil
        load()
    }
    func changeFamilyPassword(_ password: String) async {
        do {
            try await authorizedFamily { client, token in try await client.changePassword(password, token: token) }
            familyNotice = "Contraseña actualizada. Se conserva la sesión de este dispositivo; comprueba las sesiones de otros dispositivos desde el servicio si necesitas cerrarlas."
        } catch { reportFamily(error) }
    }
    func familySignOut() async {
        guard let config = familyConfiguration else { return }
        do {
            let previous = familySession
            try FamilyCredentials.delete(host: config.url.host!)
            familyAuthGeneration = UUID(); familyRefreshTask = nil
            returnToLocal(); familySession = nil; familyHomes = []
            if let previous {
                do { try await SupabaseClient(configuration: config).logout(previous.accessToken) }
                catch { familyNotice = "Se cerró la sesión en este dispositivo. No se pudo invalidar la sesión remota por conexión o caducidad; los JWT expiran según la configuración del servidor." }
            }
        } catch { reportFamily(error) }
    }
    func reportFamily(_ error: Error) {
        if let known = error as? FamilyRemoteError { self.error = known.localizedDescription }
        else if let known = error as? FinanceError { self.error = known.localizedDescription }
        else { self.error = "No se pudo completar la operación. Revisa conexión y configuración; los archivos locales se conservan." }
    }
}
