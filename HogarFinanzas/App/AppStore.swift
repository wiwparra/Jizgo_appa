import SwiftUI
import UniformTypeIdentifiers
import HogarCore

@MainActor
final class AppStore: ObservableObject {
    @Published var household: Household?
    @Published var error: String?
    @Published var readFailed = false
    @Published private(set) var demo = false
    @Published var syncStatus: SyncStatus = .localOnly
    @Published var familyEnabled = false
    @Published var familySession: FamilySession?
    @Published var familyConfiguration: SupabaseConfiguration?
    @Published var familyHomes: [FamilyHome] = []
    @Published var familyInvitations: [FamilyInvitation] = []
    @Published var familyInvitation: FamilyInvitation?
    @Published var familyConflict: FamilySnapshot?
    @Published var familyWorkspace: FamilyWorkspace?
    @Published var familyRecoveryArchiveURL: URL?
    @Published var familyArchiveURL: URL?
    @Published var familyNotice: String?
    var familyRepository: FamilyWorkspaceRepository?
    var familySyncRunning = false
    var familyGeneration = UUID()
    var familyAuthGeneration = UUID()
    var familyRefreshID = UUID()
    var familyRefreshTask: Task<FamilySession, Error>?

    private var repository: LocalRepository
    let root: URL
    var actor: UUID? {
        if familyEnabled { return familyWorkspace?.accessRevoked == false ? familySession?.user.id : nil }
        return household?.members.first(where: { $0.role == .admin && $0.active })?.id
    }
    var canManageHousehold: Bool {
        guard !readFailed, let actor, household?.members.contains(where: { $0.id == actor && $0.active && $0.role == .admin }) == true else { return false }
        return !familyEnabled || familyConflict == nil
    }
    func canEdit(_ entry: Entry) -> Bool {
        guard !readFailed, let actor, let member = household?.members.first(where: { $0.id == actor && $0.active }), !familyEnabled || familyConflict == nil else { return false }
        return member.role == .admin || entry.authorID == actor
    }
    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HogarFinanzas", isDirectory: true)
        repository = LocalRepository(url: root.appendingPathComponent("hogar.json"))
        load()
        resumeFamily()
    }
    func load() {
        if familyEnabled { reloadFamilyFromDisk(); return }
        do { household = try repository.load(); readFailed = false }
        catch { readFailed = true; self.error = error.localizedDescription }
    }
    func create(name: String, owner: String) {
        guard !readFailed, household == nil else { return }
        do {
            let new = Household(name: name, owner: Member(name: owner, role: .admin))
            try repository.save(new); household = new
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult
    func update(_ change: (inout Household, UUID) throws -> Void) -> Bool {
        guard !readFailed, var candidate = household, let actor else {
            if familyEnabled { error = "No se puede editar: revisa la sesión y el acceso al hogar." }
            return false
        }
        guard !familyEnabled || familyConflict == nil else { error = "Resuelve el conflicto familiar antes de editar de nuevo."; return false }
        do {
            try change(&candidate, actor)
            if familyEnabled {
                guard var workspace = familyWorkspace, let storage = familyRepository else { throw FinanceError.unavailable }
                try workspace.enqueue(candidate)
                try storage.save(workspace)
                familyWorkspace = workspace; syncStatus = .pending
                household = workspace.visible
                Task { await synchronizeFamily() }
            } else {
                try repository.save(candidate)
                household = candidate
            }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func exportData() throws -> Data {
        guard let household else { throw FinanceError.corrupt }
        return try Backup(household: household).encoded()
    }
    func restore(_ data: Data) {
        guard !familyEnabled else { error = "Vuelve al modo local para restaurar una copia. Una copia no sustituye al hogar compartido ni a sus permisos."; return }
        do { household = try repository.restore(data, confirmed: true); readFailed = false }
        catch { self.error = error.localizedDescription }
    }
    func setDemo(_ enabled: Bool) {
        guard !familyEnabled else { error = "Vuelve al modo local antes de activar la demostración."; return }
        demo = enabled
        repository = LocalRepository(url: root.appendingPathComponent(enabled ? "demo.json" : "hogar.json"))
        household = nil; load()
        guard enabled, household == nil, !readFailed else { return }
        create(name: "Hogar de demostración", owner: "Persona de ejemplo")
        update { home, actor in
            let bank = Account(name: "Cuenta de ejemplo", kind: .bank, opening: try Money("1000"))
            let savings = Account(name: "Ahorro de ejemplo", kind: .savings, opening: try Money("0"))
            try Ledger.addAccount(bank, to: &home, actor: actor)
            try Ledger.addAccount(savings, to: &home, actor: actor)
            try Ledger.putEntry(Entry(authorID: actor, memberID: actor, accountID: bank.id, kind: .income, amount: try Money("2000"), title: "Ingreso de ejemplo"), in: &home, actor: actor)
            try Ledger.putEntry(Entry(authorID: actor, memberID: actor, accountID: bank.id, kind: .expense, amount: try Money("500"), category: .alimentacion, title: "Compra de ejemplo"), in: &home, actor: actor)
            let goal = Goal(name: "Colchón de ejemplo", target: try Money("3000"), due: Calendar.household.date(byAdding: .month, value: 6, to: Date())!)
            try Ledger.addGoal(goal, to: &home, actor: actor)
            try Ledger.reserve(try Money("600"), goal: goal.id, in: &home, actor: actor)
            try Ledger.setBudget(Budget(month: Month(Date()), category: .alimentacion, limit: try Money("450")), in: &home, actor: actor)
        }
    }
}
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw FinanceError.corrupt }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct InlineSaveError: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        if let error = store.error {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).accessibilityLabel("Error: " + error)
        }
    }
}
