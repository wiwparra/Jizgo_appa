import XCTest
@testable import HogarCore

final class LegacyImportTests: XCTestCase {
    let member = UUID()
    func payload() -> [String: Any] {
        ["version": 1,
         "members": [["id": member.uuidString, "name": "Yo"]],
         "initialBalance": 100000,
         "movements": [
            ["id": UUID().uuidString, "title": "Nómina", "cents": 200000, "kind": "Ingreso", "category": "Otros", "memberID": member.uuidString, "date": 0],
            ["id": UUID().uuidString, "title": "Compra", "cents": 50000, "kind": "Gasto", "category": "Alimentación", "memberID": member.uuidString, "date": 0]
         ],
         "goals": [["id": UUID().uuidString, "title": "Meta", "target": 100000, "reserved": 60000, "deadline": 0]],
         "budgets": ["Alimentación": 45000, "Ocio": 0]]
    }
    func testPrototypeImportPreservesFinancialScenarioAndAttribution() throws {
        let month = try Month(year: 2026, month: 11)
        let migration = try LegacyImport(data: JSONSerialization.data(withJSONObject: payload()), budgetMonth: month)
        let home = migration.household
        let summary = home.summary(month: Month(Date(timeIntervalSinceReferenceDate: 0)))
        XCTAssertEqual(summary.balance, 250000); XCTAssertEqual(summary.expenses, 50000)
        XCTAssertEqual(summary.reserved, 60000); XCTAssertEqual(summary.unreserved, 190000)
        XCTAssertEqual(home.accounts.count, 1)
        XCTAssertEqual(home.members.count, 2)
        XCTAssertTrue(home.entries.allSatisfy { $0.authorID == nil && $0.memberID == member })
        XCTAssertEqual(home.budgets.count, 1); XCTAssertEqual(home.budgets[0].month, month)
        XCTAssertTrue(migration.warnings.contains("histórico"))
        XCTAssertEqual(try Backup.decode(Backup(household: home).encoded()), home)
    }
    func testImportedAuthorshipIsNotInventedOnEdit() throws {
        var home = try LegacyImport(data: JSONSerialization.data(withJSONObject: payload()), budgetMonth: Month(Date())).household
        var value = home.entries[0]; value.title = "Corregido"
        XCTAssertThrowsError(try Ledger.putEntry(value, in: &home, actor: member, expectedRevision: 0))
        let admin = home.members[0].id
        try Ledger.putEntry(value, in: &home, actor: admin, expectedRevision: 0)
        XCTAssertNil(home.entries[0].authorID)
    }
    func testImportRejectsCorruptAndInconsistentData() throws {
        var value = payload()
        value["version"] = 2
        XCTAssertThrowsError(try LegacyImport(data: JSONSerialization.data(withJSONObject: value), budgetMonth: Month(Date())))
        value = payload(); value["members"] = [] as [[String: Any]]
        XCTAssertThrowsError(try LegacyImport(data: JSONSerialization.data(withJSONObject: value), budgetMonth: Month(Date())))
        value = payload(); value["initialBalance"] = Int64.max
        XCTAssertThrowsError(try LegacyImport(data: JSONSerialization.data(withJSONObject: value), budgetMonth: Month(Date())))
        value = payload(); value["budgets"] = ["Categoría inventada": 100]
        XCTAssertThrowsError(try LegacyImport(data: JSONSerialization.data(withJSONObject: value), budgetMonth: Month(Date())))
        XCTAssertThrowsError(try LegacyImport(data: Data("broken".utf8), budgetMonth: Month(Date())))
    }
    func testExistingOverspendRemainsVisibleAfterImport() throws {
        var value = payload(); value["initialBalance"] = -100000
        let home = try LegacyImport(data: JSONSerialization.data(withJSONObject: value), budgetMonth: Month(Date())).household
        XCTAssertEqual(home.summary(month: Month(Date())).uncovered, 10000)
    }
    func testEditingAndDeletingGoalReleasesWithoutExpense() throws {
        var home = try LegacyImport(data: JSONSerialization.data(withJSONObject: payload()), budgetMonth: Month(Date())).household
        let admin = home.members[0].id
        let original = home.summary(month: Month(Date()))
        var goal = home.goals[0]
        goal.name = "Meta revisada"; goal.target = try Money("2000")
        try Ledger.editGoal(goal, in: &home, actor: admin)
        XCTAssertEqual(home.summary(month: Month(Date())), original)
        goal.target = try Money("500")
        XCTAssertThrowsError(try Ledger.editGoal(goal, in: &home, actor: admin))
        try Ledger.deleteGoal(goal.id, in: &home, actor: admin)
        let summary = home.summary(month: Month(Date()))
        XCTAssertEqual(summary.reserved, 0); XCTAssertEqual(summary.balance, original.balance)
        XCTAssertEqual(summary.expenses, original.expenses)
    }
    func testGoalMonthlyFormulaMatchesPrototype() throws {
        let now = Calendar.household.date(from: DateComponents(year: 2026, month: 1, day: 20))!
        let due = Calendar.household.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let goal = Goal(name: "Meta", target: try Money(cents: 100), due: due)
        XCTAssertEqual(goal.requiredMonthly(on: now), 34)
    }
    func testFailedDiskSaveKeepsParentFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let parent = directory.appendingPathComponent("not-a-directory")
        let bytes = Data("file".utf8)
        try bytes.write(to: parent)
        let repo = LocalRepository(url: parent.appendingPathComponent("home.json"))
        _ = try repo.load()
        let home = Household(name: "Hogar", owner: Member(name: "Ana", role: .admin))
        XCTAssertThrowsError(try repo.save(home))
        XCTAssertEqual(try Data(contentsOf: parent), bytes)
    }
}
