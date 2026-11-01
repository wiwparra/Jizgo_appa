import Foundation

public enum FinanceError: Error, Equatable, LocalizedError {
    case invalid(String), forbidden, conflict, insufficientFunds, corrupt, confirmationRequired, unavailable
    public var errorDescription: String? {
        switch self {
        case .invalid(let reason): return reason
        case .forbidden: return "No tienes permiso para realizar esta operación."
        case .conflict: return "Los datos han cambiado. Recarga y revisa tu modificación."
        case .insufficientFunds: return "No hay saldo sin reservar suficiente."
        case .corrupt: return "El archivo no es válido. Se conservan los datos actuales."
        case .confirmationRequired: return "Confirma antes de reemplazar los datos."
        case .unavailable: return "La colaboración familiar aún no está configurada. Los datos permanecen en este dispositivo."
        }
    }
}

/// Céntimos exactos. Límite deliberado: 90.000 millones de euros por importe.
public struct Money: Codable, Hashable, Comparable, Sendable {
    public static let limit: Int64 = 9_000_000_000_000
    public let cents: Int64
    public init(cents: Int64) throws {
        guard (-Self.limit...Self.limit).contains(cents) else { throw FinanceError.invalid("Importe fuera de rango.") }
        self.cents = cents
    }
    /// Entrada española sin agrupación: 1234,56. No admite notación exponencial ni redondeo oculto.
    public init(_ text: String) throws {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.range(of: #"^-?[0-9]{1,11}(,[0-9]{1,2})?$"#, options: .regularExpression) != nil else {
            throw FinanceError.invalid("Introduce un importe como 1234,56, sin puntos ni más de dos decimales.")
        }
        let negative = input.hasPrefix("-")
        let parts = input.replacingOccurrences(of: "-", with: "").split(separator: ",")
        let fraction = parts.count == 2 ? String(parts[1]).padding(toLength: 2, withPad: "0", startingAt: 0) : "00"
        try self.init(cents: (Int64(parts[0])! * 100 + Int64(fraction)!) * (negative ? -1 : 1))
    }
    public static func < (lhs: Money, rhs: Money) -> Bool { lhs.cents < rhs.cents }
    public var formatted: String { Self.format(cents) }
    public static func format(_ cents: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        return formatter.string(from: NSDecimalNumber(decimal: Decimal(cents) / 100)) ?? "—"
    }
    public var input: String {
        let magnitude = abs(cents)
        return "\(cents < 0 ? "-" : "")\(magnitude / 100),\(String(format: "%02lld", magnitude % 100))"
    }
}

public struct Month: Codable, Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public init(year: Int, month: Int) throws {
        guard (1900...9999).contains(year), (1...12).contains(month) else { throw FinanceError.invalid("Mes inválido.") }
        self.year = year; self.month = month
    }
    public init(_ date: Date, calendar: Calendar = .household) {
        year = calendar.component(.year, from: date); month = calendar.component(.month, from: date)
    }
    public static func < (a: Month, b: Month) -> Bool { a.year == b.year ? a.month < b.month : a.year < b.year }
    public var label: String { String(format: "%04d-%02d", year, month) }
    public var index: Int { year * 12 + month }
}
public extension Calendar {
    static var household: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Madrid")!
        value.locale = Locale(identifier: "es_ES")
        return value
    }
}
public enum Category: String, CaseIterable, Codable, Sendable {
    case vivienda = "Vivienda", alimentacion = "Alimentación", transporte = "Transporte", salud = "Salud", educacion = "Educación", ocio = "Ocio", suscripciones = "Suscripciones", otros = "Otros"
}
public enum Role: String, Codable, Sendable { case admin, member }
public struct Member: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var role: Role
    public var active: Bool
    public init(id: UUID = UUID(), name: String, role: Role, active: Bool = true) { self.id = id; self.name = name; self.role = role; self.active = active }
}
public enum AccountKind: String, CaseIterable, Codable, Sendable { case bank = "Banco", cash = "Efectivo", savings = "Ahorro" }
public struct Account: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: AccountKind
    public var opening: Money
    public init(id: UUID = UUID(), name: String, kind: AccountKind, opening: Money) { self.id = id; self.name = name; self.kind = kind; self.opening = opening }
}
public enum EntryKind: String, CaseIterable, Codable, Sendable { case income = "Ingreso", expense = "Gasto", transfer = "Transferencia" }
public struct Entry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var authorID: UUID?
    public var memberID: UUID
    public var accountID: UUID
    public var destinationID: UUID?
    public var kind: EntryKind
    public var amount: Money
    public var date: Date
    public var category: Category
    public var title: String
    public var notes: String
    public var tags: [String]
    public var revision: Int
    public var deleted: Bool
    public init(id: UUID = UUID(), authorID: UUID?, memberID: UUID, accountID: UUID, destinationID: UUID? = nil, kind: EntryKind, amount: Money, date: Date = Date(), category: Category = .otros, title: String, notes: String = "", tags: [String] = [], revision: Int = 0, deleted: Bool = false) {
        self.id = id; self.authorID = authorID; self.memberID = memberID; self.accountID = accountID; self.destinationID = destinationID; self.kind = kind; self.amount = amount; self.date = date; self.category = category; self.title = title; self.notes = notes; self.tags = tags; self.revision = revision; self.deleted = deleted
    }
    private enum CodingKeys: String, CodingKey {
        case id, authorID, memberID, accountID, destinationID, kind, amount, date, category, title, notes, tags, revision, deleted
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        authorID = try values.decodeIfPresent(UUID.self, forKey: .authorID)
        memberID = try values.decode(UUID.self, forKey: .memberID)
        accountID = try values.decode(UUID.self, forKey: .accountID)
        destinationID = try values.decodeIfPresent(UUID.self, forKey: .destinationID)
        kind = try values.decode(EntryKind.self, forKey: .kind)
        amount = try values.decode(Money.self, forKey: .amount)
        date = try values.decode(Date.self, forKey: .date)
        category = try values.decode(Category.self, forKey: .category)
        title = try values.decode(String.self, forKey: .title)
        notes = try values.decode(String.self, forKey: .notes)
        // Las copias anteriores no tenían etiquetas; conservan todos sus datos.
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        revision = try values.decode(Int.self, forKey: .revision)
        deleted = try values.decode(Bool.self, forKey: .deleted)
    }
}
public struct Budget: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var month: Month
    public var category: Category
    public var limit: Money
    public init(id: UUID = UUID(), month: Month, category: Category, limit: Money) { self.id = id; self.month = month; self.category = category; self.limit = limit }
}
public struct Goal: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var target: Money
    public var due: Date
    public var reserved: Money
    public init(id: UUID = UUID(), name: String, target: Money, due: Date, reserved: Money = try! Money(cents: 0)) { self.id = id; self.name = name; self.target = target; self.due = due; self.reserved = reserved }
    public func requiredMonthly(on date: Date) -> Int64 {
        let pending = max(0, target.cents - reserved.cents)
        let months = max(1, Month(due).index - Month(date).index + 1)
        return (pending + Int64(months) - 1) / Int64(months)
    }
    public func overdue(on date: Date) -> Bool { Calendar.household.startOfDay(for: due) < Calendar.household.startOfDay(for: date) && reserved < target }
}
public struct Household: Codable, Equatable, Sendable {
    public var schema: Int = 1
    public var id: UUID
    public var name: String
    public var members: [Member]
    public var accounts: [Account] = []
    public var entries: [Entry] = []
    public var budgets: [Budget] = []
    public var goals: [Goal] = []
    public var appliedOperations: [UUID] = []
    public init(id: UUID = UUID(), name: String, owner: Member) { self.id = id; self.name = name; self.members = [owner] }
}
