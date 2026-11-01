import XCTest
@testable import HogarCore

final class BankNoticeTests: XCTestCase {
    func testSpanishExpenseAndMerchant() throws {
        let draft = try BankNoticeParser.parse("Has realizado una compra de 12,50 EUR en CAFÉ CENTRAL con tu tarjeta terminada en 1234.")
        XCTAssertEqual(draft.amount?.cents, 1250)
        XCTAssertEqual(draft.kind, .expense)
        XCTAssertEqual(draft.suggestedTitle, "CAFÉ CENTRAL")
    }
    func testGroupedAndEnglishDecimalAmounts() throws {
        XCTAssertEqual(try BankNoticeParser.parse("Abono de 1.234,56 €").amount?.cents, 123456)
        XCTAssertEqual(try BankNoticeParser.parse("Ingreso de EUR 1 234,56").amount?.cents, 123456)
        XCTAssertEqual(try BankNoticeParser.parse("Compra de €12.50").amount?.cents, 1250)
        XCTAssertEqual(try BankNoticeParser.parse("Compra de 1.234 €").amount?.cents, 123400)
        XCTAssertEqual(try BankNoticeParser.parse("Compra de 12\u{202f}345,67 €").amount?.cents, 1234567)
        XCTAssertEqual(try BankNoticeParser.parse("Pago de -12,50 EUR").amount?.cents, 1250)
    }
    func testIncomeAndAmbiguousDirection() throws {
        XCTAssertEqual(try BankNoticeParser.parse("Has recibido un ingreso de 2000 EUR").kind, .income)
        XCTAssertNil(try BankNoticeParser.parse("Operación de 20 EUR").kind)
        XCTAssertNil(try BankNoticeParser.parse("Devolución del pago de 20 EUR").kind)
        XCTAssertNil(try BankNoticeParser.parse("Transferencia recibida por 20 EUR").kind)
    }
    func testMultipleAmountsDoNotSelectBalanceAsExpense() throws {
        let draft = try BankNoticeParser.parse("Compra de 15,50 EUR. Saldo disponible 1200 EUR.")
        XCTAssertNil(draft.amount)
        XCTAssertEqual(draft.candidates.map(\.cents), [1550,120000])
        XCTAssertNil(try BankNoticeParser.parse("Compra de 20 EUR. Saldo 20 EUR.").amount)
    }
    func testCardsDatesCodesAndMalformedAmountsAreNotAmounts() throws {
        for text in ["Tarjeta 1234, operación del 01/11/2026", "Compra de 1,234 €", "Pago de 12,345 EUR", "Pago de 0 EUR", "Saldo de 99999999999999999 EUR", "Compra de 15 USD"] {
            XCTAssertNil(try BankNoticeParser.parse(text).amount, text)
        }
    }
    func testBalanceAndForeignCurrencyAreNotGuessedAsCharge() throws {
        XCTAssertNil(try BankNoticeParser.parse("Saldo disponible: 900 EUR").amount)
        XCTAssertNil(try BankNoticeParser.parse("Compra de 20 USD. Saldo: 1000 EUR").amount)
        XCTAssertNil(try BankNoticeParser.parse("Pago devuelto de 20 EUR").kind)
    }
    func testSecurityCodesAndRejectedOperationsAreRejected() {
        for text in ["Tu código para la compra de 20 EUR es 123456", "Clave de verificación 456789", "Pago rechazado de 20 EUR", "Operación cancelada por 20 EUR", "No se ha realizado el pago de 20 EUR"] {
            XCTAssertThrowsError(try BankNoticeParser.parse(text), text)
        }
    }
    func testPendingNoticeRequiresManualChoice() throws {
        let draft = try BankNoticeParser.parse("Pago pendiente de 30 EUR")
        XCTAssertNil(draft.kind)
        XCTAssertTrue(draft.warnings.contains { $0.contains("definitivo") })
    }
    func testInputLimits() {
        XCTAssertThrowsError(try BankNoticeParser.parse(" \n"))
        XCTAssertThrowsError(try BankNoticeParser.parse(String(repeating: "A", count: 10001)))
    }
    private func fixture() throws -> (Household, UUID, Entry) {
        let owner = Member(name: "Ana", role: .admin)
        var home = Household(name: "Casa", owner: owner)
        let account = Account(name: "Banco", kind: .bank, opening: try Money("1000"))
        try Ledger.addAccount(account, to: &home, actor: owner.id)
        let entry = Entry(authorID: owner.id, memberID: owner.id, accountID: account.id, kind: .expense, amount: try Money("12,50"), category: .alimentacion, title: "Compra", tags: ["Semanal"])
        return (home, owner.id, entry)
    }
    func testNoMutationBeforeConfirmationAndIdempotentRetry() throws {
        var (home, actor, entry) = try fixture()
        let before = home
        XCTAssertThrowsError(try BankNoticeRegistration.register(entry, in: &home, actor: actor, confirmed: false))
        XCTAssertEqual(home, before)
        try BankNoticeRegistration.register(entry, in: &home, actor: actor, confirmed: true)
        let once = home
        try BankNoticeRegistration.register(entry, in: &home, actor: actor, confirmed: true)
        XCTAssertEqual(home, once)
        XCTAssertEqual(home.summary(month: Month(Date())).expenses, 1250)
    }
    func testPossibleDuplicateRequiresSeparateAcknowledgment() throws {
        var (home, actor, entry) = try fixture()
        try BankNoticeRegistration.register(entry, in: &home, actor: actor, confirmed: true)
        var another = entry; another.id = UUID()
        XCTAssertEqual(BankNoticeRegistration.possibleDuplicates(of: another, in: home).count, 1)
        XCTAssertThrowsError(try BankNoticeRegistration.register(another, in: &home, actor: actor, confirmed: true))
        XCTAssertEqual(home.entries.count, 1)
        try BankNoticeRegistration.register(another, in: &home, actor: actor, confirmed: true, duplicateAcknowledged: true)
        XCTAssertEqual(home.entries.count, 2)
    }
    func testRetryCannotResurrectDeletedMovement() throws {
        var (home, actor, entry) = try fixture()
        try BankNoticeRegistration.register(entry, in: &home, actor: actor, confirmed: true)
        try Ledger.deleteEntry(entry.id, in: &home, actor: actor, expectedRevision: 0)
        XCTAssertThrowsError(try BankNoticeRegistration.register(entry, in: &home, actor: actor, confirmed: true))
        XCTAssertTrue(home.entries[0].deleted)
    }
    func testBankRegistrationRetainsAuthorPermissions() throws {
        var (home, actor, entry) = try fixture()
        let stranger = Member(name: "Luis", role: .member); home.members.append(stranger)
        XCTAssertThrowsError(try BankNoticeRegistration.register(entry, in: &home, actor: stranger.id, confirmed: true))
        try BankNoticeRegistration.register(entry, in: &home, actor: actor, confirmed: true)
        var changed = entry; changed.amount = try Money("30")
        XCTAssertThrowsError(try BankNoticeRegistration.register(changed, in: &home, actor: actor, confirmed: true))
        XCTAssertEqual(home.entries[0].amount.cents, 1250)
    }
    func testScreenshotTextIsNotPartOfStoredDraftOrBackup() throws {
        let draft = try BankNoticeParser.parse("Compra de 12,50 EUR con tarjeta terminada en 9876")
        var (home, actor, entry) = try fixture()
        entry.id = draft.id
        try BankNoticeRegistration.register(entry, in: &home, actor: actor, confirmed: true)
        let backup = String(decoding: try Backup(household: home).encoded(), as: UTF8.self)
        XCTAssertFalse(backup.contains("terminada en 9876"))
        XCTAssertFalse(backup.contains("tarjeta"))
    }
}
