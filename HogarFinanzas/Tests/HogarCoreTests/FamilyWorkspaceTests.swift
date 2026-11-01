import XCTest
@testable import HogarCore

final class FamilyWorkspaceTests: XCTestCase {
    func fixture() throws -> (FamilyWorkspace, UUID) {
        let owner = Member(name: "Ana", role: .admin)
        let home = Household(name: "Familia", owner: owner)
        return (try FamilyWorkspace(userID: owner.id, server: FamilySnapshot(revision: 2, household: home)), owner.id)
    }
    func testImmutableQueueKeepsExpectedRevisionsAndAcknowledgesInOrder() throws {
        var (workspace, actor) = try fixture()
        var first = workspace.visible
        try Ledger.addAccount(Account(name: "Banco", kind: .bank, opening: Money("1000")), to: &first, actor: actor)
        try workspace.enqueue(first)
        let firstOperation = workspace.outbox[0]
        var second = workspace.visible
        try Ledger.setBudget(Budget(month: Month(Date()), category: .salud, limit: Money("100")), in: &second, actor: actor)
        try workspace.enqueue(second)
        XCTAssertEqual(workspace.outbox[0], firstOperation)
        XCTAssertEqual(workspace.outbox.map(\.expectedRevision), [2, 3])
        try workspace.acknowledge(FamilyReceipt(operationID: firstOperation.id, revision: 3))
        XCTAssertEqual(workspace.visible, second)
        XCTAssertEqual(workspace.server.household, first)
        try workspace.acknowledge(FamilyReceipt(operationID: workspace.outbox[0].id, revision: 4))
        XCTAssertTrue(workspace.outbox.isEmpty)
        XCTAssertEqual(workspace.server.household, second)
    }
    func testOutOfOrderOrForgedAckCannotRemovePendingChanges() throws {
        var (workspace, _) = try fixture()
        try workspace.enqueue(workspace.visible)
        let original = workspace
        XCTAssertThrowsError(try workspace.acknowledge(FamilyReceipt(operationID: UUID(), revision: 3)))
        XCTAssertThrowsError(try workspace.acknowledge(FamilyReceipt(operationID: workspace.outbox[0].id, revision: 4)))
        XCTAssertEqual(workspace, original)
    }
    func testReceiveDoesNotOverwriteOfflineChanges() throws {
        var (workspace, _) = try fixture()
        try workspace.enqueue(workspace.visible)
        let original = workspace
        var remote = workspace.server; remote.revision = 5
        XCTAssertThrowsError(try workspace.receive(remote))
        XCTAssertEqual(workspace, original)
        XCTAssertThrowsError(try workspace.replaceAfterConflict(remote, confirmed: false))
        XCTAssertEqual(workspace, original)
        try workspace.replaceAfterConflict(remote, confirmed: true)
        XCTAssertTrue(workspace.outbox.isEmpty)
        XCTAssertEqual(workspace.server.revision, 5)
    }
    func testRevokedWorkspaceCannotEnqueueOrBecomeWritableByRetry() throws {
        var (workspace, _) = try fixture()
        workspace.revokeAccess()
        XCTAssertThrowsError(try workspace.enqueue(workspace.visible))
        XCTAssertTrue(workspace.accessRevoked)
    }
    func testRemoteDifferentHomeAndStaleRevisionRejected() throws {
        var (workspace, actor) = try fixture()
        XCTAssertThrowsError(try workspace.receive(FamilySnapshot(revision: 9, household: Household(name: "Otro", owner: Member(id: actor, name: "Ana", role: .admin)))))
        var stale = workspace.server; stale.revision = 1
        XCTAssertThrowsError(try workspace.receive(stale))
    }
    func testQueueRoundTripAndCorruptFileCannotBeOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("family.json")
        let storage = FamilyWorkspaceRepository(url: url)
        XCTAssertNil(try storage.load())
        var (workspace, _) = try fixture()
        try workspace.enqueue(workspace.visible)
        try storage.save(workspace)
        let restored = try XCTUnwrap(FamilyWorkspaceRepository(url: url).load())
        XCTAssertEqual(restored, workspace)
        XCTAssertEqual(restored.outbox[0].id, workspace.outbox[0].id)
        let corrupt = Data("truncated".utf8)
        try corrupt.write(to: url)
        XCTAssertThrowsError(try storage.load())
        XCTAssertThrowsError(try storage.save(workspace))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }
    func testArchiveRetainsEntireQueueBeforeConflictReplacement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = FamilyWorkspaceRepository(url: root.appendingPathComponent("family.json"))
        _ = try storage.load()
        var (workspace, _) = try fixture()
        try workspace.enqueue(workspace.visible)
        try storage.save(workspace)
        let archive = try storage.archive(workspace)
        XCTAssertEqual(try JSONDecoder().decode(FamilyWorkspace.self, from: Data(contentsOf: archive)), workspace)
        let attributes = try FileManager.default.attributesOfItem(atPath: archive.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testMissingLocalAuthorizationOrCorruptQueueRejected() throws {
        let (workspace, _) = try fixture()
        XCTAssertThrowsError(try FamilyWorkspace(userID: UUID(), server: workspace.server))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace)) as? [String: Any])
        json["outbox"] = [["id": UUID().uuidString,"expectedRevision": -1,"snapshot": try JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace.visible))]]
        let corrupt = try JSONDecoder().decode(FamilyWorkspace.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try corrupt.validate())
    }
    func testLocalMigrationDoesNotInventVerifiedAuthorsOrDeleteOriginal() throws {
        let (workspace, actor) = try fixture()
        let localOwner = Member(name: "Nombre local", role: .admin)
        var local = Household(name: "Hogar previo", owner: localOwner)
        let bank = Account(name: "Banco", kind: .bank, opening: try Money("1000"))
        try Ledger.addAccount(bank, to: &local, actor: localOwner.id)
        try Ledger.putEntry(Entry(authorID: localOwner.id, memberID: localOwner.id, accountID: bank.id, kind: .expense, amount: Money("100"), title: "Compra", tags: ["Semanal"]), in: &local, actor: localOwner.id)
        let original = local
        let copied = try FamilyMigration.copyLocal(local, into: workspace.visible, actor: actor)
        XCTAssertEqual(local, original)
        XCTAssertEqual(copied.id, workspace.visible.id)
        XCTAssertNil(copied.entries[0].authorID)
        XCTAssertEqual(copied.entries[0].memberID, actor)
        XCTAssertTrue(copied.entries[0].notes.contains("Nombre local"))
        XCTAssertEqual(copied.entries[0].tags, ["Semanal"])
        XCTAssertEqual(copied.summary(month: Month(Date())).balance, local.summary(month: Month(Date())).balance)
        XCTAssertThrowsError(try FamilyMigration.copyLocal(local, into: copied, actor: actor))
    }
    func testCorruptCacheRecoveryRequiresConfirmationAndPreservesOriginalBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("family.json")
        let corrupt = Data("unreadable pending data".utf8)
        try corrupt.write(to: file)
        let storage = FamilyWorkspaceRepository(url: file)
        XCTAssertThrowsError(try storage.load())
        let (workspace, actor) = try fixture()
        XCTAssertThrowsError(try storage.recover(from: workspace.server, userID: actor, confirmed: false))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
        let (recovered, archive) = try storage.recover(from: workspace.server, userID: actor, confirmed: true)
        XCTAssertEqual(try Data(contentsOf: archive), corrupt)
        XCTAssertEqual(recovered, workspace)
        XCTAssertEqual(try storage.load(), workspace)
    }
    func testOversizedRevisionIsRejectedBeforeQueueArithmetic() throws {
        let (workspace, _) = try fixture()
        var snapshot = workspace.server; snapshot.revision = Int.max
        XCTAssertThrowsError(try snapshot.validate())
    }
    func testAdminCanKeepHistoricalAttributionAfterRevocation() throws {
        var (workspace, actor) = try fixture()
        var home = workspace.visible
        let member = Member(name: "Luis", role: .member)
        home.members.append(member)
        let account = Account(name: "Banco", kind: .bank, opening: try Money("100"))
        try Ledger.addAccount(account, to: &home, actor: actor)
        var entry = Entry(authorID: actor, memberID: member.id, accountID: account.id, kind: .expense, amount: try Money("10"), title: "Gasto anterior")
        try Ledger.putEntry(entry, in: &home, actor: actor)
        try Ledger.revoke(member.id, in: &home, actor: actor)
        entry.title = "Corrección histórica"
        try Ledger.putEntry(entry, in: &home, actor: actor, expectedRevision: 0)
        XCTAssertEqual(home.entries[0].memberID, member.id)
        try workspace.enqueue(home)
        XCTAssertEqual(workspace.visible.entries[0].title, "Corrección histórica")
    }

}
