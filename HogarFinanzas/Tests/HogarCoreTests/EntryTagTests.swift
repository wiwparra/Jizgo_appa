import XCTest
@testable import HogarCore

final class EntryTagTests: XCTestCase {
    func testNormalizeTagsWithoutLosingDisplayNames() throws {
        XCTAssertEqual(try EntryTags.parse(" Compra semanal, VACACIONES, compra semanal, vacaciones, ,Colegio "), ["Compra semanal", "VACACIONES", "Colegio"])
        XCTAssertEqual(try EntryTags.parse("Educación, educacion"), ["Educación"])
        XCTAssertEqual(try EntryTags.parse(" , "), [])
    }
    func testTagValidation() throws {
        XCTAssertThrowsError(try EntryTags.parse(String(repeating: "x", count: 33)))
        XCTAssertThrowsError(try EntryTags.parse((1...11).map { "tag\($0)" }.joined(separator: ",")))
        XCTAssertThrowsError(try EntryTags.parse("línea\ninterior"))
        XCTAssertFalse(EntryTags.valid(["Casa", "CASA"]))
        XCTAssertFalse(EntryTags.valid([" casa "]))
        XCTAssertFalse(EntryTags.valid(["casa,ocio"]))
    }
    private func fixture() throws -> (Household, UUID, Entry) {
        let owner = Member(name: "Ana", role: .admin)
        var home = Household(name: "Casa", owner: owner)
        let account = Account(name: "Banco", kind: .bank, opening: try Money("1000"))
        try Ledger.addAccount(account, to: &home, actor: owner.id)
        let entry = Entry(authorID: owner.id, memberID: owner.id, accountID: account.id, kind: .expense, amount: try Money("10"), title: "Compra", tags: ["Educación", "Colegio"])
        return (home, owner.id, entry)
    }
    func testTagsAreSearchableAndFilterableWithoutChangingTotals() throws {
        var (home, actor, entry) = try fixture()
        try Ledger.putEntry(entry, in: &home, actor: actor)
        let original = home.summary(month: Month(Date()))
        XCTAssertEqual(home.filtered(EntryFilter(tag: "educacion")).count, 1)
        XCTAssertEqual(home.filtered(EntryFilter(query: "COLEGIO")).count, 1)
        XCTAssertEqual(home.filtered(EntryFilter(tag: "otro")).count, 0)
        var revised = entry; revised.tags = ["Vacaciones"]
        try Ledger.putEntry(revised, in: &home, actor: actor, expectedRevision: 0)
        XCTAssertEqual(home.summary(month: Month(Date())), original)
        XCTAssertEqual(home.filtered(EntryFilter(tag: "Colegio")).count, 0)
    }
    func testTagRoundTripAndBackwardsCompatibility() throws {
        var (home, actor, entry) = try fixture()
        try Ledger.putEntry(entry, in: &home, actor: actor)
        let data = try Backup(household: home).encoded()
        XCTAssertEqual(try Backup.decode(data).entries[0].tags, entry.tags)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var payload = try XCTUnwrap(json["household"] as? [String: Any])
        var entries = try XCTUnwrap(payload["entries"] as? [[String: Any]])
        entries[0].removeValue(forKey: "tags")
        payload["entries"] = entries; json["household"] = payload
        let old = try Backup.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.entries[0].tags, [])
        XCTAssertEqual(old.entries[0].amount, entry.amount)
    }
    func testInvalidTagsInBackupOrMutationAreRejected() throws {
        var (home, actor, entry) = try fixture()
        entry.tags = ["x", "X"]
        XCTAssertThrowsError(try Ledger.putEntry(entry, in: &home, actor: actor))
        XCTAssertTrue(home.entries.isEmpty)
        home.entries = [entry]
        XCTAssertThrowsError(try home.validate())
    }
}
