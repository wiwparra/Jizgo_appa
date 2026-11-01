import Foundation

/// Propuesta transitoria. Nunca almacena el texto bancario ni modifica el hogar al analizarlo.
public struct BankNoticeDraft: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let amount: Money?
    public let candidates: [Money]
    public let kind: EntryKind?
    public let suggestedTitle: String
    public let warnings: [String]
}
public enum BankNoticeParser {
    public static func parse(_ input: String) throws -> BankNoticeDraft {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, input.count <= 10000 else { throw FinanceError.invalid("Pega un aviso de hasta 10.000 caracteres.") }
        let text = input.replacingOccurrences(of: "\u{00a0}", with: " ").replacingOccurrences(of: "\u{202f}", with: " ")
        let normalized = EntryTags.key(text)
        if contains(#"\b(codigo|contrasena|clave|verificacion|otp)\b"#, normalized) {
            throw FinanceError.invalid("Este texto parece contener una clave o un código de seguridad. No lo importes como movimiento.")
        }
        if contains(#"\b(rechazad[oa]|denegad[oa]|cancelad[oa]|anulad[oa])\b|no se ha (realizado|efectuado)"#, normalized) {
            throw FinanceError.invalid("El aviso indica una operación rechazada o cancelada. No se preparará un cargo como si se hubiera realizado.")
        }
        // Solo importes acompañados de EUR o €. Nunca números de tarjeta, fechas o códigos sueltos.
        let number = #"[+-]?(?:[0-9]{1,3}(?:[. ][0-9]{3})+(?:,[0-9]{1,2})?|[0-9]+(?:[,.][0-9]{1,2})?)"#
        let pattern = #"(?i)(?<![A-Za-z0-9.,])(?:EUR\b|€)\s*("# + number + #")(?![0-9.,])|(?<![A-Za-z0-9.,])("# + number + #")\s*(?:EUR\b|€)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        var values: [Money] = []
        for match in matches {
            let range = match.range(at: match.range(at: 1).location == NSNotFound ? 2 : 1)
            var token = source.substring(with: range).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "-", with: "")
            if token.contains(",") { token = token.replacingOccurrences(of: ".", with: "") }
            else if let dot = token.lastIndex(of: "."), token.distance(from: dot, to: token.endIndex) == 3 { token = token.replacingOccurrences(of: ".", with: ",") }
            else { token = token.replacingOccurrences(of: ".", with: "") }
            guard let money = try? Money(token), money.cents > 0 else { continue }
            values.append(money)
        }
        let foreignCurrency = contains(#"\b(usd|gbp|chf|dolares|libras)\b|[$£]"#, normalized)
        let balanceOnly: Bool
        if let match = matches.first, matches.count == 1 {
            let start = max(0, match.range.location - 55)
            let prefix = source.substring(with: NSRange(location: start, length: match.range.location - start))
            balanceOnly = contains(#"(saldo|disponible|limite|restante|balance)[^.;\n]{0,45}$"#, EntryTags.key(prefix))
        } else { balanceOnly = false }
        let unambiguousAmount = matches.count == 1 && values.count == 1 && !balanceOnly && !foreignCurrency
        let pending = contains(#"\b(pendiente|retencion|preautorizacion)\b"#, normalized)
        let transfer = contains(#"\b(transferencia|traspaso)\b"#, normalized)
        let income = contains(#"\b(abono|ingreso|nomina|recibido|recibida|devolucion|devuelto|devuelta|reembolso)\b"#, normalized)
        let expense = contains(#"\b(pago|compra|cargo|pagado|recibo)\b"#, normalized)
        let kind: EntryKind? = pending || transfer || income == expense ? nil : (income ? .income : .expense)
        var warnings = ["Revisa siempre la fecha y la cuenta: no se deducen del aviso. No se guarda nada hasta que lo confirmes."]
        if !unambiguousAmount { warnings.append("No se ha identificado un único importe inequívoco. Introduce el importe correcto; no confundas el saldo con el movimiento.") }
        if foreignCurrency { warnings.append("Hay una moneda distinta de EUR. Comprueba el cargo final en euros: no se realiza conversión automática.") }
        if balanceOnly { warnings.append("El importe identificado parece un saldo, no el valor de una operación. No se ha rellenado automáticamente.") }
        if kind == nil { warnings.append("Selecciona el tipo de movimiento. Una transferencia propia no es un ingreso ni un gasto.") }
        if pending { warnings.append("El aviso parece pendiente o una retención. Comprueba que el movimiento sea definitivo antes de registrarlo.") }
        var title = ""
        if !transfer, let expression = try? NSRegularExpression(pattern: #"(?i)\ben\s+([\p{L}][\p{L}0-9 &'-]{1,70}?)(?=\s+(?:con|por|el|saldo|tarjeta)\b|[.;\n]|$)"#),
           let match = expression.firstMatch(in: text, range: NSRange(location: 0, length: source.length)) {
            let candidate = source.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if !EntryTags.key(candidate).hasPrefix("tu cuenta") { title = candidate }
        }
        return BankNoticeDraft(id: UUID(), amount: unambiguousAmount ? values[0] : nil, candidates: Array(Set(values)).sorted(), kind: kind, suggestedTitle: title, warnings: warnings)
    }
    private static func contains(_ pattern: String, _ text: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
}
public enum BankNoticeRegistration {
    public static func possibleDuplicates(of entry: Entry, in household: Household) -> [Entry] {
        household.entries.filter {
            !$0.deleted && $0.id != entry.id && $0.accountID == entry.accountID && $0.kind == entry.kind &&
            $0.amount == entry.amount && Calendar.household.isDate($0.date, inSameDayAs: entry.date)
        }
    }
    public static func register(_ entry: Entry, in household: inout Household, actor: UUID, confirmed: Bool, duplicateAcknowledged: Bool = false) throws {
        _ = try household.authorized(actor)
        guard confirmed else { throw FinanceError.confirmationRequired }
        guard entry.authorID == actor else { throw FinanceError.forbidden }
        // Reintentar la misma propuesta no duplica ni resucita un registro eliminado.
        if let saved = household.entries.first(where: { $0.id == entry.id }) {
            guard saved == entry, !saved.deleted else { throw FinanceError.conflict }
            return
        }
        guard duplicateAcknowledged || possibleDuplicates(of: entry, in: household).isEmpty else {
            throw FinanceError.invalid("Ya hay un movimiento con esa cuenta, fecha, tipo e importe. Revísalo y confirma expresamente si se trata de otro.")
        }
        try Ledger.putEntry(entry, in: &household, actor: actor)
    }
}
