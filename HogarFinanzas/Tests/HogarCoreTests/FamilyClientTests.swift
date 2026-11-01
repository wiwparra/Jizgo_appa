import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import HogarCore

final class FamilyClientTests: XCTestCase, @unchecked Sendable {
    func config() throws -> SupabaseConfiguration { try SupabaseConfiguration(url: "https://hogartest.supabase.co", publicKey: "sb_publishable_test_key_123456789") }
    func testConfigurationRejectsSecretsAndInsecureEndpoints() throws {
        for url in ["http://hogartest.supabase.co", "https://attacker.invalid", "https://hogartest.supabase.co@attacker.invalid", "https://hogartest.supabase.co/path", "https://hogartest.supabase.co?key=secret", "https://hogartest.supabase.co:8080"] {
            XCTAssertThrowsError(try SupabaseConfiguration(url: url, publicKey: config().publicKey))
        }
        for key in ["sb_secret_private", "service_role", "", "sb_publishable_test_key_123456789\r\nHeader: secret"] {
            XCTAssertThrowsError(try SupabaseConfiguration(url: config().url.absoluteString, publicKey: key))
        }
        let anon = Data(#"{"role":"anon"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        XCTAssertNoThrow(try SupabaseConfiguration(url: config().url.absoluteString, publicKey: "header." + anon + ".signature"))
        let service = Data(#"{"role":"service_role"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        XCTAssertThrowsError(try SupabaseConfiguration(url: config().url.absoluteString, publicKey: "header." + service + ".signature"))
    }
    func testSignInUsesAuthEndpointAndDoesNotSendActorIdentity() async throws {
        let id = UUID()
        let session = FamilySession(accessToken: "access-test", refreshToken: "refresh-test", expiresAt: Date().timeIntervalSince1970 + 3600, user: FamilyUser(id: id, email: "ana@example.invalid"))
        let response = try JSONEncoder().encode(session)
        let client = try SupabaseClient(configuration: config()) { request in
            XCTAssertEqual(request.url?.path, "/auth/v1/token")
            XCTAssertEqual(request.url?.query, "grant_type=password")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(body["email"] as? String, "ana@example.invalid")
            XCTAssertNil(body["actor"])
            return (response, 200)
        }
        let signedIn = try await client.signIn(email: "ana@example.invalid", password: "test-only-password")
        XCTAssertEqual(signedIn.user.id, id)
    }
    func testRefreshCannotSilentlySwitchAccounts() async throws {
        let old = FamilySession(accessToken: "a", refreshToken: "r", expiresAt: 0, user: FamilyUser(id: UUID(), email: nil))
        let other = FamilySession(accessToken: "b", refreshToken: "s", expiresAt: 9999999999, user: FamilyUser(id: UUID(), email: nil))
        let response = try JSONEncoder().encode(other)
        let client = try SupabaseClient(configuration: config()) { _ in (response,200) }
        do { _ = try await client.refresh(old); XCTFail("Debe conservar la identidad") }
        catch { XCTAssertEqual(error as? FamilyRemoteError, .authentication) }
    }
    func testFinancialRPCUsesJwtAndStableOperationInsteadOfTrustingClientActor() async throws {
        let owner = Member(name: "Ana", role: .admin)
        let home = Household(name: "Casa", owner: owner)
        let operation = FamilyOperation(expectedRevision: 4, snapshot: home)
        let receipt = FamilyReceipt(operationID: operation.id, revision: 5)
        let response = try JSONEncoder().encode(receipt)
        let client = try SupabaseClient(configuration: config()) { request in
            XCTAssertEqual(request.url?.path, "/rest/v1/rpc/family_commit")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-jwt")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "apikey"))
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(body["p_operation"] as? String, operation.id.uuidString)
            XCTAssertEqual(body["p_expected"] as? Int, 4)
            XCTAssertNil(body["actor"])
            XCTAssertNil(body["p_user"])
            return (response, 200)
        }
        let received = try await client.commit(home: home.id, operation: operation, token: "test-jwt")
        XCTAssertEqual(received.operationID, operation.id)
    }
    func testServerErrorsAreMappedWithoutLeakingPayloads() async throws {
        let cases: [(Int,String,FamilyRemoteError)] = [(403,"access_revoked",.accessRevoked),(403,"admin_required",.forbidden),(409,"conflict",.conflict),(422,"last_admin",.lastAdmin),(422,"insufficient_unreserved",.insufficientFunds),(403,"email_unconfirmed",.unconfirmedEmail),(503,"private financial content",.unavailable)]
        for (status, message, expected) in cases {
            let response = try JSONSerialization.data(withJSONObject: ["message": message, "details": "private financial content"])
            let client = try SupabaseClient(configuration: config()) { _ in (response,status) }
            do { _ = try await client.fetch(home: UUID(), token: "test"); XCTFail("Se esperaba error") }
            catch {
                XCTAssertEqual(error as? FamilyRemoteError, expected)
                XCTAssertFalse(error.localizedDescription.contains("private financial content"))
            }
        }
    }
    func testInvalidJsonAndEmptySigninAreNotAcceptedAsSuccess() async throws {
        let client = try SupabaseClient(configuration: config()) { _ in (Data("{}".utf8),200) }
        do { _ = try await client.signIn(email: "ana@example.invalid", password: "test-password"); XCTFail("Debe haber sesión real") }
        catch { XCTAssertEqual(error as? FamilyRemoteError, .invalidData) }
    }
    func testPasswordChangeUsesAuthenticatedPutAndRejectsShortPasswords() async throws {
        let user = FamilyUser(id: UUID(), email: "ana@example.invalid")
        let data = try JSONEncoder().encode(user)
        let client = try SupabaseClient(configuration: config()) { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/auth/v1/user")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-jwt")
            return (data,200)
        }
        try await client.changePassword("test-new-password", token: "test-jwt")
        do { try await client.changePassword("short", token: "test-jwt"); XCTFail("La contraseña debe validarse") }
        catch { XCTAssertNotNil(error as? FinanceError) }
    }

    func testInvalidRemoteHouseholdIsRejectedBeforePresentation() async throws {
        let owner = Member(name: "Ana", role: .admin)
        var home = Household(name: "Casa", owner: owner)
        let account = Account(name: "Banco", kind: .bank, opening: try Money("100"))
        home.accounts = [account]
        let entry = Entry(authorID: owner.id, memberID: owner.id, accountID: account.id, kind: .expense, amount: try Money("10"), title: "Prueba")
        home.entries = [entry,entry]
        let data = try JSONEncoder().encode(FamilySnapshot(revision: 0, household: home))
        let client = try SupabaseClient(configuration: config()) { _ in (data,200) }
        do { _ = try await client.fetch(home: home.id, token: "test-jwt"); XCTFail("No se deben presentar UUID duplicados") }
        catch { XCTAssertEqual(error as? FamilyRemoteError, .invalidData) }
    }

}
