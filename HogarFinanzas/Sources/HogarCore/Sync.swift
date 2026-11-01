import Foundation

public enum SyncStatus: Equatable, Sendable {
    case localOnly, pending, syncing, synced, error(String)
    public var label: String {
        switch self {
        case .localOnly: return "Solo en este dispositivo"
        case .pending: return "Pendiente"
        case .syncing: return "Sincronizando"
        case .synced: return "Sincronizado"
        case .error(let message): return "Error: \(message)"
        }
    }
}
/// Contrato de una futura autoridad remota. El servidor debe derivar actor de la sesión autenticada.
/// NO usar UUID recibido del cliente como autenticación.
public struct EntryOperation: Codable, Equatable, Sendable {
    public var id: UUID
    public var entry: Entry
    public var expectedRevision: Int?
    public var delete: Bool
    public init(id: UUID = UUID(), entry: Entry, expectedRevision: Int? = nil, delete: Bool = false) {
        self.id = id; self.entry = entry; self.expectedRevision = expectedRevision; self.delete = delete
    }
}
/// Reductor puro comprobable. No es un servicio de sincronización ni autentica cuentas Apple.
public enum SyncReducer {
    public static func apply(_ operation: EntryOperation, to household: inout Household, authenticatedActor: UUID) throws {
        _ = try household.authorized(authenticatedActor)
        if household.appliedOperations.contains(operation.id) { return }
        var candidate = household
        if operation.delete {
            guard let revision = operation.expectedRevision else { throw FinanceError.conflict }
            try Ledger.deleteEntry(operation.entry.id, in: &candidate, actor: authenticatedActor, expectedRevision: revision)
        } else {
            try Ledger.putEntry(operation.entry, in: &candidate, actor: authenticatedActor, expectedRevision: operation.expectedRevision)
        }
        candidate.appliedOperations.append(operation.id)
        try candidate.validate()
        household = candidate
    }
}
/// No se simula éxito sin una autoridad remota configurada.
public struct UnconfiguredFamilyService: Sendable {
    public init() {}
    public func invite() throws -> URL { throw FinanceError.unavailable }
    public func synchronize() async throws { throw FinanceError.unavailable }
}
