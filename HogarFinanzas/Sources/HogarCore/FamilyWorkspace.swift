import Foundation

public struct FamilySnapshot: Codable, Equatable, Sendable {
    public var revision: Int
    public var household: Household
    public init(revision: Int, household: Household) { self.revision = revision; self.household = household }
    private enum CodingKeys: String, CodingKey { case revision, household }
    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        revision = try fields.decode(Int.self, forKey: .revision)
        household = try fields.decode(Household.self, forKey: .household)
        try validate()
    }
    public func validate() throws {
        guard (0...1_000_000_000).contains(revision) else { throw FinanceError.corrupt }
        try household.validate()
    }
}
public struct FamilyOperation: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let expectedRevision: Int
    public let snapshot: Household
    public init(id: UUID = UUID(), expectedRevision: Int, snapshot: Household) { self.id = id; self.expectedRevision = expectedRevision; self.snapshot = snapshot }
}
public struct FamilyReceipt: Codable, Sendable {
    public let operationID: UUID
    public let revision: Int
    public init(operationID: UUID, revision: Int) { self.operationID = operationID; self.revision = revision }
}
/// Cola persistente e inmutable: incluso si se pierde el ACK se reenvía el mismo UUID con el mismo cuerpo.
public struct FamilyWorkspace: Codable, Equatable, Sendable {
    public let userID: UUID
    public private(set) var server: FamilySnapshot
    public private(set) var outbox: [FamilyOperation] = []
    public private(set) var accessRevoked = false
    public var visible: Household { outbox.last?.snapshot ?? server.household }
    public init(userID: UUID, server: FamilySnapshot) throws {
        self.userID = userID; self.server = server
        try validate()
        _ = try server.household.authorized(userID)
    }
    public func validate() throws {
        try server.validate()
        guard outbox.count <= 100, Set(outbox.map(\.id)).count == outbox.count else { throw FinanceError.corrupt }
        for (index, operation) in outbox.enumerated() {
            guard operation.snapshot.id == server.household.id, operation.expectedRevision == server.revision + index else { throw FinanceError.corrupt }
            try operation.snapshot.validate()
        }
    }
    public mutating func enqueue(_ household: Household) throws {
        guard !accessRevoked else { throw FinanceError.forbidden }
        _ = try visible.authorized(userID)
        guard household.id == server.household.id, outbox.count < 100 else { throw FinanceError.invalid("Sincroniza o resuelve las modificaciones pendientes antes de continuar.") }
        try household.validate()
        guard try JSONEncoder().encode(household).count <= 16 * 1024 * 1024 else { throw FinanceError.invalid("El hogar supera el límite de sincronización de 16 MB.") }
        outbox.append(FamilyOperation(expectedRevision: server.revision + outbox.count, snapshot: household))
    }
    public mutating func acknowledge(_ receipt: FamilyReceipt) throws {
        guard let first = outbox.first, first.id == receipt.operationID, receipt.revision == first.expectedRevision + 1 else { throw FinanceError.conflict }
        server = FamilySnapshot(revision: receipt.revision, household: first.snapshot)
        outbox.removeFirst()
    }
    public mutating func receive(_ snapshot: FamilySnapshot) throws {
        guard outbox.isEmpty, snapshot.household.id == server.household.id, snapshot.revision >= server.revision else { throw FinanceError.conflict }
        try snapshot.validate()
        _ = try snapshot.household.authorized(userID)
        server = snapshot; accessRevoked = false
    }
    public mutating func revokeAccess() { accessRevoked = true }
    /// Solo después de archivar íntegramente esta instancia y obtener confirmación del usuario.
    public mutating func replaceAfterConflict(_ snapshot: FamilySnapshot, confirmed: Bool) throws {
        guard confirmed else { throw FinanceError.confirmationRequired }
        var candidate = self; candidate.outbox = []
        try candidate.receive(snapshot)
        self = candidate
    }
}
public final class FamilyWorkspaceRepository {
    public let url: URL
    private var writable = false
    public init(url: URL) { self.url = url }
    public func load() throws -> FamilyWorkspace? {
        writable = false
        guard FileManager.default.fileExists(atPath: url.path) else { writable = true; return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= 64 * 1024 * 1024 else { throw FinanceError.corrupt }
        do {
            let workspace = try JSONDecoder().decode(FamilyWorkspace.self, from: Data(contentsOf: url))
            try workspace.validate(); writable = true; return workspace
        } catch { throw FinanceError.corrupt }
    }
    public func save(_ workspace: FamilyWorkspace) throws {
        guard writable else { throw FinanceError.corrupt }
        try workspace.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(workspace)
        guard data.count <= 64 * 1024 * 1024 else { throw FinanceError.invalid("La cola local supera 64 MB. Sincroniza o conserva una copia antes de continuar.") }
        try ProtectedFile.write(data, to: url)
    }
    public func recover(from snapshot: FamilySnapshot, userID: UUID, confirmed: Bool) throws -> (FamilyWorkspace, URL) {
        guard confirmed else { throw FinanceError.confirmationRequired }
        let recovered = try FamilyWorkspace(userID: userID, server: snapshot)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= 64 * 1024 * 1024 else { throw FinanceError.corrupt }
        let bytes = try Data(contentsOf: url)
        let archive = url.deletingLastPathComponent().appendingPathComponent("ilegible-\(UUID().uuidString).json")
        try ProtectedFile.write(bytes, to: archive)
        let previous = writable
        writable = true
        do { try save(recovered); return (recovered, archive) }
        catch { writable = previous; throw error }
    }
    public func archive(_ workspace: FamilyWorkspace) throws -> URL {
        try workspace.validate()
        let archive = url.deletingLastPathComponent().appendingPathComponent("conflicto-\(UUID().uuidString).json")
        try ProtectedFile.write(JSONEncoder().encode(workspace), to: archive)
        return archive
    }
}
/// Los autores locales no son identidades verificadas. Al publicar una copia se conserva autor desconocido.
public enum FamilyMigration {
    public static func copyLocal(_ local: Household, into remote: Household, actor: UUID) throws -> Household {
        _ = try remote.authorized(actor, admin: true)
        guard remote.accounts.isEmpty, remote.entries.isEmpty, remote.goals.isEmpty, remote.budgets.isEmpty else { throw FinanceError.invalid("Solo se puede copiar el hogar local a un hogar familiar vacío.") }
        try local.validate()
        var result = remote
        result.accounts = local.accounts; result.budgets = local.budgets; result.goals = local.goals
        result.entries = try local.entries.map { entry in
            var value = entry
            let attribution = local.members.first { $0.id == entry.memberID }?.name ?? "Desconocido"
            let note = "Importación local. Atribución anterior: \(attribution). Autor histórico sin verificar."
            value.notes = entry.notes.isEmpty ? note : entry.notes + "\n" + note
            guard value.notes.count <= 1000 else { throw FinanceError.invalid("Una nota importada supera el límite. Conserva la copia y acorta esa nota antes de publicar.") }
            value.authorID = nil; value.memberID = actor
            value.revision = 0
            // Los eliminados se conservan como tombstones en la copia local; no se publican como nuevos movimientos.
            return value
        }.filter { !$0.deleted }
        try result.validate()
        return result
    }
}
