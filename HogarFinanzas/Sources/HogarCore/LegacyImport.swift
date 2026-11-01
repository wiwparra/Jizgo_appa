import Foundation

/// Importación explícita del JSON de HogarFinanzas-0.1. Nunca modifica el archivo original.
public struct LegacyImport: Sendable {
    public let household: Household
    public let warnings: String
    public init(data: Data, budgetMonth: Month) throws {
        guard data.count <= 64 * 1024 * 1024 else { throw FinanceError.corrupt }
        do {
            let legacy = try JSONDecoder().decode(LegacyHousehold.self, from: data)
            guard legacy.version == 1, !legacy.members.isEmpty, legacy.members.count <= 999,
                  legacy.movements.count <= 100_000, legacy.goals.count <= 1000,
                  legacy.budgets.count <= Category.allCases.count else { throw FinanceError.corrupt }
            let owner = Member(name: "Propietario local de la importación", role: .admin)
            var result = Household(name: "Hogar importado del prototipo", owner: owner)
            result.members += legacy.members.map { Member(id: $0.id, name: $0.name, role: .member) }
            let account = Account(name: "Cuenta conjunta importada", kind: .bank, opening: try Money(cents: legacy.initialBalance))
            result.accounts = [account]
            result.entries = try legacy.movements.map {
                guard let category = Category(rawValue: $0.category), let kind = EntryKind(rawValue: $0.kind), kind != .transfer else { throw FinanceError.corrupt }
                // El prototipo solo tenía atribución; no permite recuperar autoría autenticada.
                return Entry(id: $0.id, authorID: nil, memberID: $0.memberID, accountID: account.id, kind: kind, amount: try Money(cents: $0.cents), date: $0.date, category: category, title: $0.title, notes: "Importado del prototipo 0.1. Autor histórico desconocido.")
            }
            result.goals = try legacy.goals.map { Goal(id: $0.id, name: $0.title, target: try Money(cents: $0.target), due: $0.deadline, reserved: try Money(cents: $0.reserved)) }
            result.budgets = try legacy.budgets.sorted(by: { $0.key < $1.key }).compactMap { key, cents in
                guard let category = Category(rawValue: key), cents >= 0 else { throw FinanceError.corrupt }
                return cents == 0 ? nil : Budget(month: budgetMonth, category: category, limit: try Money(cents: cents))
            }
            try result.validate()
            household = result
            warnings = "Todos los movimientos se agrupan en una cuenta conjunta. No se conoce su autor histórico; se conservan los miembros atribuidos como etiquetas locales. Los límites recurrentes solo se importan a \(budgetMonth.label): el prototipo no conservaba historial. Las reservas existentes se mantienen, incluida cualquier falta de cobertura."
        } catch { throw FinanceError.corrupt }
    }
}
private struct LegacyHousehold: Decodable {
    let version: Int
    let members: [LegacyMember]
    let initialBalance: Int64
    let movements: [LegacyMovement]
    let goals: [LegacyGoal]
    let budgets: [String: Int64]
}
private struct LegacyMember: Decodable { let id: UUID; let name: String }
private struct LegacyMovement: Decodable {
    let id: UUID; let title: String; let cents: Int64; let kind: String
    let category: String; let memberID: UUID; let date: Date
}
private struct LegacyGoal: Decodable {
    let id: UUID; let title: String; let target: Int64; let reserved: Int64; let deadline: Date
}
