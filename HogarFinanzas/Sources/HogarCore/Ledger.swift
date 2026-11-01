import Foundation

public struct EntryFilter: Sendable {
    public var month: Month?
    public var category: Category?
    public var account: UUID?
    public var member: UUID?
    public var tag: String?
    public var query: String = ""
    public init(month: Month? = nil, category: Category? = nil, account: UUID? = nil, member: UUID? = nil, tag: String? = nil, query: String = "") {
        self.month = month; self.category = category; self.account = account; self.member = member; self.tag = tag; self.query = query
    }
}
public struct Summary: Equatable, Sendable {
    public var balance: Int64
    public var income: Int64
    public var expenses: Int64
    public var reserved: Int64
    public var result: Int64 { income - expenses }
    public var unreserved: Int64 { balance - reserved }
    public var uncovered: Int64 { max(0, reserved - balance) }
}
public struct BudgetStatus: Sendable {
    public var consumed: Int64
    public var limit: Int64
    public var remaining: Int64 { max(0, limit - consumed) }
    public var excess: Int64 { max(0, consumed - limit) }
}
public extension Household {
    func filtered(_ filter: EntryFilter) -> [Entry] {
        entries.filter { entry in
            !entry.deleted && (filter.month == nil || Month(entry.date) == filter.month) &&
            (filter.category == nil || entry.category == filter.category) &&
            (filter.account == nil || entry.accountID == filter.account || entry.destinationID == filter.account) &&
            (filter.member == nil || entry.memberID == filter.member) &&
            (filter.tag == nil || EntryTags.key(filter.tag!).isEmpty || entry.tags.contains(where: { EntryTags.key($0) == EntryTags.key(filter.tag!) })) &&
            (filter.query.isEmpty || (entry.title + " " + entry.notes + " " + entry.tags.joined(separator: " ")).localizedCaseInsensitiveContains(filter.query))
        }.sorted { $0.date > $1.date }
    }
    func balance(account id: UUID) -> Int64 {
        let opening = accounts.first { $0.id == id }?.opening.cents ?? 0
        return entries.filter { !$0.deleted }.reduce(opening) { result, entry in
            var next = result
            if entry.accountID == id { next += entry.kind == .income ? entry.amount.cents : -entry.amount.cents }
            if entry.kind == .transfer && entry.destinationID == id { next += entry.amount.cents }
            return next
        }
    }
    func summary(month: Month) -> Summary {
        let period = filtered(EntryFilter(month: month))
        return Summary(balance: accounts.reduce(0) { $0 + balance(account: $1.id) }, income: period.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount.cents }, expenses: period.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount.cents }, reserved: goals.reduce(0) { $0 + $1.reserved.cents })
    }
    func budgetStatus(_ budget: Budget) -> BudgetStatus {
        BudgetStatus(consumed: filtered(EntryFilter(month: budget.month, category: budget.category)).filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount.cents }, limit: budget.limit.cents)
    }
    /// Validación también aplicada a archivos decodificados: Codable no ejecuta los inicializadores validadores.
    func validate() throws {
        guard schema == 1, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              members.count <= 1000, accounts.count <= 1000, entries.count <= 100_000,
              budgets.count <= 100_000, goals.count <= 1000, appliedOperations.count <= 100_000,
              members.contains(where: { $0.active && $0.role == .admin }) else { throw FinanceError.corrupt }
        func unique<T: Hashable>(_ ids: [T]) -> Bool { Set(ids).count == ids.count }
        guard unique(members.map(\.id)), unique(accounts.map(\.id)), unique(entries.map(\.id)), unique(budgets.map(\.id)), unique(goals.map(\.id)), unique(appliedOperations),
              unique(budgets.map { "\($0.month.label):\($0.category.rawValue)" }) else { throw FinanceError.corrupt }
        let memberIDs = Set(members.map(\.id)), accountIDs = Set(accounts.map(\.id))
        func money(_ amount: Money, positive: Bool = false) -> Bool {
            (-Money.limit...Money.limit).contains(amount.cents) && (!positive || amount.cents > 0)
        }
        func text(_ value: String, required: Bool = true) -> Bool { value.count <= 1000 && (!required || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        func validDate(_ date: Date) -> Bool {
            date.timeIntervalSince1970.isFinite && (-2_208_988_800...253_402_214_400).contains(date.timeIntervalSince1970)
        }
        guard text(name), members.allSatisfy({ text($0.name) }), accounts.allSatisfy({ text($0.name) && money($0.opening) }),
              entries.allSatisfy({ entry in
                  (entry.authorID == nil || memberIDs.contains(entry.authorID!)) && memberIDs.contains(entry.memberID) && accountIDs.contains(entry.accountID) && money(entry.amount, positive: true) && text(entry.title) && text(entry.notes, required: false) && EntryTags.valid(entry.tags) && validDate(entry.date) && (0...1_000_000).contains(entry.revision) &&
                  (entry.kind == .transfer ? (entry.destinationID != entry.accountID && entry.destinationID.map { accountIDs.contains($0) } == true) : entry.destinationID == nil)
              }), budgets.allSatisfy({ (1900...9999).contains($0.month.year) && (1...12).contains($0.month.month) && money($0.limit, positive: true) }),
              goals.allSatisfy({ text($0.name) && validDate($0.due) && money($0.target, positive: true) && money($0.reserved) && $0.reserved.cents >= 0 && $0.reserved <= $0.target }) else { throw FinanceError.corrupt }
    }
    func authorized(_ actor: UUID, admin: Bool = false) throws -> Member {
        guard let member = members.first(where: { $0.id == actor && $0.active }), !admin || member.role == .admin else { throw FinanceError.forbidden }
        return member
    }
}

/// Todas las mutaciones pasan por esta capa. La identidad la suministra el repositorio, nunca el miembro atribuido.
public enum Ledger {
    private static func commit(_ household: inout Household, _ change: (inout Household) throws -> Void) throws {
        var candidate = household
        try change(&candidate)
        try candidate.validate()
        household = candidate
    }
    public static func addAccount(_ account: Account, to household: inout Household, actor: UUID) throws {
        _ = try household.authorized(actor, admin: true)
        try commit(&household) { $0.accounts.append(account) }
    }
    public static func putEntry(_ entry: Entry, in household: inout Household, actor: UUID, expectedRevision: Int? = nil) throws {
        let principal = try household.authorized(actor)
        guard EntryTags.valid(entry.tags) else { throw FinanceError.invalid("Revisa las etiquetas: máximo 10, distintas y de hasta 32 caracteres.") }
        guard entry.amount.cents > 0 else { throw FinanceError.invalid("El importe del movimiento debe ser positivo.") }
        guard !entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FinanceError.invalid("Escribe un concepto.") }
        if entry.kind == .transfer {
            guard let destination = entry.destinationID, destination != entry.accountID, household.accounts.contains(where: { $0.id == destination }) else { throw FinanceError.invalid("Selecciona una cuenta de destino diferente a la de origen.") }
        }
        let previousMember = household.entries.first(where: { $0.id == entry.id })?.memberID
        guard household.members.contains(where: { $0.id == entry.memberID && ($0.active || previousMember == entry.memberID) }) else { throw FinanceError.invalid("Miembro inactivo.") }
        try commit(&household) { candidate in
            if let index = candidate.entries.firstIndex(where: { $0.id == entry.id }) {
                let old = candidate.entries[index]
                guard principal.role == .admin || old.authorID == actor else { throw FinanceError.forbidden }
                guard !old.deleted, expectedRevision == old.revision, entry.authorID == old.authorID, !entry.deleted else { throw FinanceError.conflict }
                var updated = entry; updated.revision = old.revision + 1
                candidate.entries[index] = updated
            } else {
                guard entry.authorID == actor, entry.revision == 0, !entry.deleted, expectedRevision == nil else { throw FinanceError.forbidden }
                candidate.entries.append(entry)
            }
        }
    }
    public static func deleteEntry(_ id: UUID, in household: inout Household, actor: UUID, expectedRevision: Int) throws {
        let principal = try household.authorized(actor)
        try commit(&household) { candidate in
            guard let index = candidate.entries.firstIndex(where: { $0.id == id }) else { throw FinanceError.invalid("Movimiento inexistente.") }
            guard principal.role == .admin || candidate.entries[index].authorID == actor else { throw FinanceError.forbidden }
            guard candidate.entries[index].revision == expectedRevision, !candidate.entries[index].deleted else { throw FinanceError.conflict }
            candidate.entries[index].deleted = true; candidate.entries[index].revision += 1
        }
    }
    public static func setBudget(_ budget: Budget, in household: inout Household, actor: UUID) throws {
        _ = try household.authorized(actor, admin: true)
        guard budget.limit.cents > 0 else { throw FinanceError.invalid("El límite mensual debe ser positivo.") }
        try commit(&household) { candidate in
            if let index = candidate.budgets.firstIndex(where: { $0.month == budget.month && $0.category == budget.category }) {
                candidate.budgets[index].limit = budget.limit
            } else { candidate.budgets.append(budget) }
        }
    }
    public static func addGoal(_ goal: Goal, to household: inout Household, actor: UUID) throws {
        _ = try household.authorized(actor, admin: true)
        guard goal.target.cents > 0, !goal.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FinanceError.invalid("Indica un nombre y un objetivo positivo.") }
        guard goal.reserved.cents == 0 else { throw FinanceError.invalid("Crea la meta sin reservas y aporta después.") }
        try commit(&household) { $0.goals.append(goal) }
    }
    public static func editGoal(_ goal: Goal, in household: inout Household, actor: UUID) throws {
        _ = try household.authorized(actor, admin: true)
        guard goal.target.cents > 0, goal.target >= goal.reserved, !goal.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FinanceError.invalid("El objetivo debe ser positivo y cubrir lo ya reservado. Revisa también el nombre.") }
        try commit(&household) { candidate in
            guard let index = candidate.goals.firstIndex(where: { $0.id == goal.id }), goal.reserved == candidate.goals[index].reserved else { throw FinanceError.conflict }
            candidate.goals[index] = goal
        }
    }
    public static func deleteGoal(_ id: UUID, in household: inout Household, actor: UUID) throws {
        _ = try household.authorized(actor, admin: true)
        try commit(&household) { candidate in
            guard candidate.goals.contains(where: { $0.id == id }) else { throw FinanceError.invalid("Meta inexistente.") }
            candidate.goals.removeAll { $0.id == id }
        }
    }
    public static func reserve(_ amount: Money, goal id: UUID, in household: inout Household, actor: UUID) throws {
        _ = try household.authorized(actor, admin: true)
        try commit(&household) { candidate in
            guard amount.cents != 0, let index = candidate.goals.firstIndex(where: { $0.id == id }) else { throw FinanceError.invalid("Reserva inválida.") }
            let summary = candidate.summary(month: Month(Date()))
            if amount.cents > 0 && amount.cents > summary.unreserved { throw FinanceError.insufficientFunds }
            let next = candidate.goals[index].reserved.cents + amount.cents
            guard next >= 0 && next <= candidate.goals[index].target.cents else { throw FinanceError.invalid("La reserva debe estar entre cero y el objetivo.") }
            candidate.goals[index].reserved = try Money(cents: next)
        }
    }
    public static func revoke(_ memberID: UUID, in household: inout Household, actor: UUID) throws {
        _ = try household.authorized(actor, admin: true)
        try commit(&household) { candidate in
            guard let index = candidate.members.firstIndex(where: { $0.id == memberID }) else { throw FinanceError.forbidden }
            candidate.members[index].active = false
        }
    }
    public static func leave(_ household: inout Household, actor: UUID) throws {
        _ = try household.authorized(actor)
        try commit(&household) { candidate in
            let index = candidate.members.firstIndex { $0.id == actor }!
            candidate.members[index].active = false
        }
    }
}
