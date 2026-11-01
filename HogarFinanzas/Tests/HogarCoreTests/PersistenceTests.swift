import XCTest
@testable import HogarCore

final class PersistenceTests: XCTestCase {
    func withRepository(_ body: (LocalRepository, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("hogar.json")
        try body(LocalRepository(url: url), url)
    }
    func home() -> Household { Household(name: "Hogar", owner: Member(name: "Ana", role: .admin)) }
    func testPersistenceRoundTrip() throws {
        try withRepository { repo, url in
            XCTAssertNil(try repo.load())
            let original = home()
            try repo.save(original)
            XCTAssertEqual(try LocalRepository(url: url).load(), original)
            let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(permissions?.intValue, 0o600)
        }
    }
    func testBackupRoundTripAndConfirmation() throws {
        try withRepository { repo, _ in
            let original = home(), data = try Backup(household: original).encoded()
            XCTAssertEqual(try Backup.decode(data), original)
            XCTAssertThrowsError(try repo.restore(data, confirmed: false))
            XCTAssertEqual(try repo.restore(data, confirmed: true), original)
            XCTAssertEqual(try repo.load(), original)
        }
    }
    func testCorruptReadCannotOverwriteOriginal() throws {
        try withRepository { repo, url in
            let corrupt = Data("{truncated".utf8)
            try corrupt.write(to: url)
            XCTAssertThrowsError(try repo.load())
            XCTAssertThrowsError(try repo.save(home()))
            XCTAssertEqual(try Data(contentsOf: url), corrupt)
            XCTAssertThrowsError(try repo.restore(corrupt, confirmed: true))
            XCTAssertEqual(try Data(contentsOf: url), corrupt)
            _ = try repo.restore(Backup(household: home()).encoded(), confirmed: true)
            XCTAssertNotNil(try repo.load())
        }
    }
    func testInvalidRestorePreservesValidFile() throws {
        try withRepository { repo, url in
            _ = try repo.load(); try repo.save(home())
            let original = try Data(contentsOf: url)
            XCTAssertThrowsError(try repo.restore(Data("{}".utf8), confirmed: true))
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }
    func testMalformedBackupValidation() throws {
        let valid = try Backup(household: home()).encoded()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        json["version"] = 999
        XCTAssertThrowsError(try Backup.decode(JSONSerialization.data(withJSONObject: json)))
        json["version"] = 1; json["format"] = "OtraApp"
        XCTAssertThrowsError(try Backup.decode(JSONSerialization.data(withJSONObject: json)))
        XCTAssertThrowsError(try Backup.decode(Data()))
    }
    func testDecodedMoneyAndReferencesAreValidated() throws {
        var home = home()
        let account = Account(name: "Banco", kind: .bank, opening: try Money("10"))
        try Ledger.addAccount(account, to: &home, actor: home.members[0].id)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Backup(household: home).encoded()) as? [String: Any])
        var payload = try XCTUnwrap(json["household"] as? [String: Any])
        var accounts = try XCTUnwrap(payload["accounts"] as? [[String: Any]])
        accounts[0]["opening"] = ["cents": Int64.max]
        payload["accounts"] = accounts; json["household"] = payload
        XCTAssertThrowsError(try Backup.decode(JSONSerialization.data(withJSONObject: json)))
        var entry = Entry(authorID: home.members[0].id, memberID: home.members[0].id, accountID: UUID(), kind: .expense, amount: try Money("1"), title: "Prueba")
        home.entries = [entry]
        XCTAssertThrowsError(try home.validate())
        entry.accountID = account.id; home.entries = [entry, entry]
        XCTAssertThrowsError(try home.validate())
    }
    func testInvalidSaveDoesNotReplaceFile() throws {
        try withRepository { repo, url in
            _ = try repo.load()
            var value = home(); try repo.save(value)
            let original = try Data(contentsOf: url)
            value.members = []
            XCTAssertThrowsError(try repo.save(value))
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }
    func testLoadRequiredBeforeSave() throws {
        try withRepository { repo, _ in XCTAssertThrowsError(try repo.save(home())) }
    }
    func testExportRetainsTombstonesAndOperationIDs() throws {
        var home = home()
        let actor = home.members[0].id
        let account = Account(name: "Banco", kind: .bank, opening: try Money("100"))
        try Ledger.addAccount(account, to: &home, actor: actor)
        let entry = Entry(authorID: actor, memberID: actor, accountID: account.id, kind: .expense, amount: try Money("10"), title: "Compra")
        let operation = EntryOperation(entry: entry)
        try SyncReducer.apply(operation, to: &home, authenticatedActor: actor)
        try Ledger.deleteEntry(entry.id, in: &home, actor: actor, expectedRevision: 0)
        let restored = try Backup.decode(Backup(household: home).encoded())
        XCTAssertTrue(restored.entries[0].deleted)
        XCTAssertEqual(restored.appliedOperations, [operation.id])
    }
}
