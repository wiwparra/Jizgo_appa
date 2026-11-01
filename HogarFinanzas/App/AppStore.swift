import SwiftUI
import UniformTypeIdentifiers
import HogarCore

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var household: Household?
    @Published var error: String?
    @Published private(set) var readFailed = false
    @Published private(set) var demo = false
    let syncStatus: SyncStatus = .localOnly
    private var repository: LocalRepository
    private let root: URL
    var actor: UUID? { household?.members.first(where: { $0.role == .admin && $0.active })?.id }
    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HogarFinanzas", isDirectory: true)
        repository = LocalRepository(url: root.appendingPathComponent("hogar.json"))
        load()
    }
    func load() {
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
        guard !readFailed, var candidate = household, let actor else { return false }
        do {
            try change(&candidate, actor)
            try repository.save(candidate)
            household = candidate
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func exportData() throws -> Data {
        guard let household else { throw FinanceError.corrupt }
        return try Backup(household: household).encoded()
    }
    func restore(_ data: Data) {
        do { household = try repository.restore(data, confirmed: true); readFailed = false }
        catch { self.error = error.localizedDescription }
    }
    func setDemo(_ enabled: Bool) {
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
