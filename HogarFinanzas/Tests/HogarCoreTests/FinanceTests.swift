import XCTest
@testable import HogarCore

final class FinanceTests: XCTestCase {
    func fixture() throws -> (Household, UUID, Account, Account) {
        let owner = Member(name: "Ana", role: .admin)
        var home = Household(name: "Casa", owner: owner)
        let bank = Account(name: "Banco", kind: .bank, opening: try Money("1000"))
        let cash = Account(name: "Efectivo", kind: .cash, opening: try Money("0"))
        try Ledger.addAccount(bank, to: &home, actor: owner.id)
        try Ledger.addAccount(cash, to: &home, actor: owner.id)
        return (home, owner.id, bank, cash)
    }
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func entry(_ actor: UUID, _ account: Account, _ amount: String, kind: EntryKind = .expense, on: Date = Date()) throws -> Entry {
        Entry(authorID: actor, memberID: actor, accountID: account.id, kind: kind, amount: try Money(amount), date: on, category: .alimentacion, title: "Movimiento")
    }
    func testExactMoney() throws {
        XCTAssertEqual(try Money("0,10").cents + Money("0,20").cents, 30)
        XCTAssertEqual(try Money("12,5").cents, 1250)
        XCTAssertEqual(try Money("-0,01").cents, -1)
        XCTAssertEqual(try Money(" 1000,01 ").input, "1000,01")
    }
    func testRejectAmbiguousMoney() {
        for text in ["1.000,00", "1.23", "1,234", "1e3", "NaN", "", "1,", "+1", "--2", "999999999999999999", "90000000001"] {
            XCTAssertThrowsError(try Money(text), text)
        }
        XCTAssertThrowsError(try Money(cents: Int64.max))
    }
    func testMinimumFinancialScenario() throws {
        var (home, actor, bank, cash) = try fixture()
        try Ledger.putEntry(entry(actor, bank, "2000", kind: .income), in: &home, actor: actor)
        try Ledger.putEntry(entry(actor, bank, "500"), in: &home, actor: actor)
        let goal = Goal(name: "Colchón", target: try Money("1000"), due: Date())
        try Ledger.addGoal(goal, to: &home, actor: actor)
        try Ledger.reserve(Money("600"), goal: goal.id, in: &home, actor: actor)
        let summary = home.summary(month: Month(Date()))
        XCTAssertEqual(summary.balance, 250000); XCTAssertEqual(summary.income, 200000)
        XCTAssertEqual(summary.expenses, 50000); XCTAssertEqual(summary.reserved, 60000)
        XCTAssertEqual(summary.unreserved, 190000); XCTAssertEqual(summary.result, 150000)
        let transfer = Entry(authorID: actor, memberID: actor, accountID: bank.id, destinationID: cash.id, kind: .transfer, amount: try Money("300"), title: "Retirada")
        try Ledger.putEntry(transfer, in: &home, actor: actor)
        XCTAssertEqual(home.summary(month: Month(Date())), summary)
        XCTAssertEqual(home.balance(account: bank.id), 220000); XCTAssertEqual(home.balance(account: cash.id), 30000)
    }
    func testOpeningIsNotIncome() throws {
        let (home, _, _, _) = try fixture()
        XCTAssertEqual(home.summary(month: Month(Date())).income, 0)
        XCTAssertEqual(home.summary(month: Month(Date())).balance, 100000)
    }
    func testEditDeleteRecalculate() throws {
        var (home, actor, bank, _) = try fixture()
        var expense = try entry(actor, bank, "100")
        try Ledger.putEntry(expense, in: &home, actor: actor)
        expense.amount = try Money("250")
        try Ledger.putEntry(expense, in: &home, actor: actor, expectedRevision: 0)
        XCTAssertEqual(home.balance(account: bank.id), 75000)
        XCTAssertEqual(home.entries[0].revision, 1)
        try Ledger.deleteEntry(expense.id, in: &home, actor: actor, expectedRevision: 1)
        XCTAssertEqual(home.balance(account: bank.id), 100000)
        XCTAssertEqual(home.filtered(EntryFilter()).count, 0)
        XCTAssertTrue(home.entries[0].deleted)
        XCTAssertThrowsError(try Ledger.putEntry(expense, in: &home, actor: actor, expectedRevision: 2))
    }
    func testChangingKindAndAccountRecalculates() throws {
        var (home, actor, bank, cash) = try fixture()
        var value = try entry(actor, bank, "50")
        try Ledger.putEntry(value, in: &home, actor: actor)
        value.kind = .income; value.accountID = cash.id
        try Ledger.putEntry(value, in: &home, actor: actor, expectedRevision: 0)
        XCTAssertEqual(home.balance(account: bank.id), 100000)
        XCTAssertEqual(home.balance(account: cash.id), 5000)
    }
    func testInvalidTransferAndNegativeAmountAreAtomic() throws {
        var (home, actor, bank, _) = try fixture()
        let original = home
        var transfer = try entry(actor, bank, "2", kind: .transfer)
        transfer.destinationID = bank.id
        XCTAssertThrowsError(try Ledger.putEntry(transfer, in: &home, actor: actor))
        transfer.destinationID = UUID()
        XCTAssertThrowsError(try Ledger.putEntry(transfer, in: &home, actor: actor))
        XCTAssertThrowsError(try Ledger.putEntry(entry(actor, bank, "-1"), in: &home, actor: actor))
        XCTAssertThrowsError(try Ledger.putEntry(entry(actor, bank, "0"), in: &home, actor: actor))
        XCTAssertEqual(home, original)
    }
    func testMadridMonthBoundaryAndLeapYear() throws {
        var (home, actor, bank, _) = try fixture()
        try Ledger.putEntry(entry(actor, bank, "10", on: date("2024-02-29T22:59:59Z")), in: &home, actor: actor)
        try Ledger.putEntry(entry(actor, bank, "20", on: date("2024-02-29T23:00:00Z")), in: &home, actor: actor)
        XCTAssertEqual(home.summary(month: try Month(year: 2024, month: 2)).expenses, 1000)
        XCTAssertEqual(home.summary(month: try Month(year: 2024, month: 3)).expenses, 2000)
        XCTAssertThrowsError(try Month(year: 2024, month: 13))
    }
    func testYearBoundaryAndDST() throws {
        XCTAssertEqual(Month(date("2024-12-31T23:00:00Z")), try Month(year: 2025, month: 1))
        XCTAssertEqual(Month(date("2024-03-31T22:00:00Z")), try Month(year: 2024, month: 4))
    }
    func testFilters() throws {
        var (home, actor, bank, cash) = try fixture()
        var value = try entry(actor, bank, "10")
        value.title = "Café del barrio"; value.notes = "Con familia"
        try Ledger.putEntry(value, in: &home, actor: actor)
        XCTAssertEqual(home.filtered(EntryFilter(category: .alimentacion, account: bank.id, member: actor, query: "FAMILIA")).count, 1)
        XCTAssertEqual(home.filtered(EntryFilter(account: cash.id)).count, 0)
        XCTAssertEqual(home.filtered(EntryFilter(category: .salud)).count, 0)
    }
    func testReservationsCannotBeDuplicatedOrOverbooked() throws {
        var (home, actor, _, _) = try fixture()
        let goal = Goal(name: "Meta A", target: try Money("2000"), due: Date())
        let other = Goal(name: "Meta B", target: try Money("2000"), due: Date())
        try Ledger.addGoal(goal, to: &home, actor: actor); try Ledger.addGoal(other, to: &home, actor: actor)
        try Ledger.reserve(Money("600"), goal: goal.id, in: &home, actor: actor)
        let before = home
        XCTAssertThrowsError(try Ledger.reserve(Money("401"), goal: other.id, in: &home, actor: actor))
        XCTAssertEqual(home, before)
        try Ledger.reserve(Money("-100"), goal: goal.id, in: &home, actor: actor)
        XCTAssertEqual(home.goals[0].reserved.cents, 50000)
        XCTAssertThrowsError(try Ledger.reserve(Money("-501"), goal: goal.id, in: &home, actor: actor))
        XCTAssertEqual(home.summary(month: Month(Date())).expenses, 0)
    }
    func testGoalTargetLimit() throws {
        var (home, actor, _, _) = try fixture()
        let goal = Goal(name: "Meta", target: try Money("100"), due: Date())
        try Ledger.addGoal(goal, to: &home, actor: actor)
        XCTAssertThrowsError(try Ledger.reserve(Money("101"), goal: goal.id, in: &home, actor: actor))
        XCTAssertThrowsError(try Ledger.addGoal(Goal(name: "Preasignada", target: Money("100"), due: Date(), reserved: Money("10")), to: &home, actor: actor))
    }
    func testLaterExpenseExposesUncoveredReserves() throws {
        var (home, actor, bank, _) = try fixture()
        let goal = Goal(name: "Meta", target: try Money("1000"), due: Date())
        try Ledger.addGoal(goal, to: &home, actor: actor)
        try Ledger.reserve(Money("900"), goal: goal.id, in: &home, actor: actor)
        try Ledger.putEntry(entry(actor, bank, "500"), in: &home, actor: actor)
        let status = home.summary(month: Month(Date()))
        XCTAssertEqual(status.expenses, 50000); XCTAssertEqual(status.uncovered, 40000)
        XCTAssertEqual(status.unreserved, -40000)
        try Ledger.reserve(Money("-400"), goal: goal.id, in: &home, actor: actor)
        XCTAssertEqual(home.summary(month: Month(Date())).uncovered, 0)
    }
    func testGoalDeadlinesAndCeiling() throws {
        let goal = Goal(name: "Meta", target: try Money("100,01"), due: date("2025-03-31T12:00:00Z"))
        XCTAssertEqual(goal.requiredMonthly(on: date("2025-01-01T12:00:00Z")), 3334)
        XCTAssertFalse(goal.overdue(on: date("2025-03-31T13:00:00Z")))
        XCTAssertTrue(goal.overdue(on: date("2025-04-01T12:00:00Z")))
        XCTAssertEqual(goal.requiredMonthly(on: date("2026-01-01T12:00:00Z")), 10001)
    }
    func testBudgetHistoryAndOverspend() throws {
        var (home, actor, bank, _) = try fixture()
        let jan = try Month(year: 2025, month: 1), feb = try Month(year: 2025, month: 2)
        try Ledger.setBudget(Budget(month: jan, category: .alimentacion, limit: Money("100")), in: &home, actor: actor)
        try Ledger.setBudget(Budget(month: feb, category: .alimentacion, limit: Money("200")), in: &home, actor: actor)
        try Ledger.setBudget(Budget(month: feb, category: .alimentacion, limit: Money("300")), in: &home, actor: actor)
        try Ledger.putEntry(entry(actor, bank, "125", on: date("2025-01-15T12:00:00Z")), in: &home, actor: actor)
        XCTAssertEqual(home.budgets.count, 2); XCTAssertEqual(home.budgets[0].limit.cents, 10000)
        let status = home.budgetStatus(home.budgets[0])
        XCTAssertEqual(status.excess, 2500); XCTAssertEqual(status.remaining, 0)
        XCTAssertEqual(home.budgetStatus(home.budgets[1]).consumed, 0)
    }
    func testAuthorAndAttributedMemberDiffer() throws {
        var (home, actor, bank, _) = try fixture()
        let other = Member(name: "Luis", role: .member); home.members.append(other)
        var value = try entry(actor, bank, "10"); value.memberID = other.id
        try Ledger.putEntry(value, in: &home, actor: actor)
        XCTAssertEqual(home.entries[0].authorID, actor)
        XCTAssertThrowsError(try Ledger.deleteEntry(value.id, in: &home, actor: other.id, expectedRevision: 0))
    }
    func testMemberCanEditOwnAdminCanEditAll() throws {
        var (home, actor, bank, _) = try fixture()
        let other = Member(name: "Luis", role: .member); home.members.append(other)
        var value = try entry(other.id, bank, "10")
        try Ledger.putEntry(value, in: &home, actor: other.id)
        value.amount = try Money("20")
        try Ledger.putEntry(value, in: &home, actor: other.id, expectedRevision: 0)
        value.amount = try Money("30")
        try Ledger.putEntry(value, in: &home, actor: actor, expectedRevision: 1)
        XCTAssertEqual(home.entries[0].amount.cents, 3000)
        var forged = value; forged.authorID = actor
        XCTAssertThrowsError(try Ledger.putEntry(forged, in: &home, actor: actor, expectedRevision: 2))
    }
    func testMemberCannotManageConfiguration() throws {
        var (home, _, bank, _) = try fixture()
        let member = Member(name: "Luis", role: .member); home.members.append(member)
        XCTAssertThrowsError(try Ledger.addAccount(bank, to: &home, actor: member.id))
        XCTAssertThrowsError(try Ledger.setBudget(Budget(month: Month(Date()), category: .salud, limit: Money("10")), in: &home, actor: member.id))
        XCTAssertThrowsError(try Ledger.addGoal(Goal(name: "Meta", target: Money("10"), due: Date()), to: &home, actor: member.id))
    }
    func testRevocationAndLeaving() throws {
        var (home, actor, bank, _) = try fixture()
        let other = Member(name: "Luis", role: .member); home.members.append(other)
        try Ledger.revoke(other.id, in: &home, actor: actor)
        XCTAssertThrowsError(try Ledger.putEntry(entry(other.id, bank, "10"), in: &home, actor: other.id))
        XCTAssertThrowsError(try Ledger.leave(&home, actor: actor)) // último administrador
        XCTAssertTrue(home.members[0].active)
        let active = Member(name: "Eva", role: .member); home.members.append(active)
        try Ledger.leave(&home, actor: active.id)
        XCTAssertFalse(home.members.last!.active)
    }
    func testRetryIsIdempotentAndDeleteIsTombstone() throws {
        var (home, actor, bank, _) = try fixture()
        let operation = EntryOperation(entry: try entry(actor, bank, "25"))
        try SyncReducer.apply(operation, to: &home, authenticatedActor: actor)
        try SyncReducer.apply(operation, to: &home, authenticatedActor: actor)
        XCTAssertEqual(home.entries.count, 1); XCTAssertEqual(home.balance(account: bank.id), 97500)
        let deletion = EntryOperation(entry: operation.entry, expectedRevision: 0, delete: true)
        try SyncReducer.apply(deletion, to: &home, authenticatedActor: actor)
        try SyncReducer.apply(deletion, to: &home, authenticatedActor: actor)
        XCTAssertTrue(home.entries[0].deleted); XCTAssertEqual(home.balance(account: bank.id), 100000)
        XCTAssertThrowsError(try SyncReducer.apply(EntryOperation(entry: operation.entry), to: &home, authenticatedActor: actor))
    }
    func testOfflineConflictDoesNotOverwrite() throws {
        var (home, actor, bank, _) = try fixture()
        var value = try entry(actor, bank, "10")
        try SyncReducer.apply(EntryOperation(entry: value), to: &home, authenticatedActor: actor)
        value.amount = try Money("20")
        try SyncReducer.apply(EntryOperation(entry: value, expectedRevision: 0), to: &home, authenticatedActor: actor)
        let saved = home
        value.amount = try Money("30")
        XCTAssertThrowsError(try SyncReducer.apply(EntryOperation(entry: value, expectedRevision: 0), to: &home, authenticatedActor: actor))
        XCTAssertEqual(home, saved)
    }
    func testRevokedActorCannotRetryAcknowledgedOperation() throws {
        var (home, actor, bank, _) = try fixture()
        let member = Member(name: "Luis", role: .member); home.members.append(member)
        let operation = EntryOperation(entry: try entry(member.id, bank, "25"))
        try SyncReducer.apply(operation, to: &home, authenticatedActor: member.id)
        try Ledger.revoke(member.id, in: &home, actor: actor)
        XCTAssertThrowsError(try SyncReducer.apply(operation, to: &home, authenticatedActor: member.id))
    }
    func testUnconfiguredServiceFailsClosed() async throws {
        XCTAssertThrowsError(try UnconfiguredFamilyService().invite())
        do { try await UnconfiguredFamilyService().synchronize(); XCTFail("No debe simular éxito") }
        catch { XCTAssertEqual(error as? FinanceError, .unavailable) }
        XCTAssertEqual(SyncStatus.pending.label, "Pendiente")
        XCTAssertEqual(SyncStatus.syncing.label, "Sincronizando")
        XCTAssertEqual(SyncStatus.synced.label, "Sincronizado")
    }
}
