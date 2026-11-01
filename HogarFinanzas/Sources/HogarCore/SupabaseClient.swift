import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum FamilyRemoteError: Error, Equatable, LocalizedError, Sendable {
    case invalidConfiguration, authentication, unconfirmedEmail, accessRevoked, forbidden, conflict, invalidData, lastAdmin, insufficientFunds, unavailable
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Usa la URL HTTPS de tu proyecto Supabase y su clave pública publishable/anon. Nunca una clave secret o service_role."
        case .authentication: "La sesión no es válida. Vuelve a iniciar sesión con tu correo y contraseña."
        case .unconfirmedEmail: "Confirma tu correo antes de entrar en el hogar."
        case .accessRevoked: "Se ha revocado tu acceso al hogar. Los cambios pendientes se conservan bloqueados en este dispositivo."
        case .forbidden: "No tienes acceso a este hogar o permiso para esta operación."
        case .conflict: "Otra persona ha cambiado el hogar. Revisa el conflicto antes de sincronizar; tus cambios locales se conservan."
        case .invalidData: "Revisa los datos. La operación no es válida o la invitación ha caducado, se ha revocado o corresponde a otro correo."
        case .lastAdmin: "Debe quedar al menos un administrador activo. Promueve a otro miembro antes de salir."
        case .insufficientFunds: "El saldo compartido no cubre esta reserva. Revisa los cambios del hogar."
        case .unavailable: "El servicio no responde o no está configurado. Se conservan los datos locales; comprueba la conexión y la configuración."
        }
    }
}
public struct SupabaseConfiguration: Codable, Equatable, Sendable {
    public let url: URL
    public let publicKey: String
    public init(url: String, publicKey: String) throws {
        let address = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: address), parsed.scheme == "https", let host = parsed.host,
              host.hasSuffix(".supabase.co"), host.split(separator: ".").count == 3, parsed.user == nil, parsed.password == nil,
              parsed.port == nil, parsed.query == nil, parsed.fragment == nil, parsed.path == "" || parsed.path == "/" else { throw FamilyRemoteError.invalidConfiguration }
        let key = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count <= 8192, key.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else { throw FamilyRemoteError.invalidConfiguration }
        if key.hasPrefix("sb_publishable_"), key.count > 20, key.count < 2048 { }
        else {
            let parts = key.split(separator: ".")
            guard parts.count == 3, parts[0].count > 0, parts[2].count > 0 else { throw FamilyRemoteError.invalidConfiguration }
            var body = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            body += String(repeating: "=", count: (4 - body.count % 4) % 4)
            guard let bytes = Data(base64Encoded: body), let payload = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], payload["role"] as? String == "anon" else { throw FamilyRemoteError.invalidConfiguration }
        }
        self.url = URL(string: "https://" + host)!
        self.publicKey = key
    }
    public func validated() throws -> SupabaseConfiguration { try Self(url: url.absoluteString, publicKey: publicKey) }
}
public struct FamilyUser: Codable, Equatable, Sendable {
    public var id: UUID
    public var email: String?
    public init(id: UUID, email: String?) { self.id = id; self.email = email }
}
public struct FamilySession: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: TimeInterval
    public var user: FamilyUser
    public init(accessToken: String, refreshToken: String, expiresAt: TimeInterval, user: FamilyUser) { self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresAt = expiresAt; self.user = user }
    public var requiresRefresh: Bool { expiresAt < Date().timeIntervalSince1970 + 60 }
    private enum CodingKeys: String, CodingKey { case accessToken = "access_token", refreshToken = "refresh_token", expiresAt = "expires_at", user }
}
public struct FamilyHome: Decodable, Identifiable, Sendable { public let id: UUID; public let name: String; public let role: Role }
public struct FamilyInvitation: Decodable, Identifiable, Sendable { public let id: UUID; public let token: String?; public let email: String; public let expiresAt: TimeInterval }
public typealias FamilyHTTPTransport = @Sendable (URLRequest) async throws -> (Data, Int)

/// Cliente REST sin SDK externo. El JWT de Supabase identifica al actor; nunca se envía un actor arbitrario a los RPC.
public struct SupabaseClient: Sendable {
    public let configuration: SupabaseConfiguration
    private let transport: FamilyHTTPTransport
    public init(configuration: SupabaseConfiguration, transport: FamilyHTTPTransport? = nil) throws {
        self.configuration = try configuration.validated()
        self.transport = transport ?? { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, data.count <= 64 * 1024 * 1024 else { throw FamilyRemoteError.unavailable }
            return (data, http.statusCode)
        }
    }
    public func signIn(email: String, password: String) async throws -> FamilySession {
        try await request(path: "auth/v1/token", query: "grant_type=password", body: ["email": email, "password": password], token: nil)
    }
    public func refresh(_ session: FamilySession) async throws -> FamilySession {
        let refreshed: FamilySession = try await request(path: "auth/v1/token", query: "grant_type=refresh_token", body: ["refresh_token": session.refreshToken], token: nil)
        guard refreshed.user.id == session.user.id else { throw FamilyRemoteError.authentication }
        return refreshed
    }
    public func signUp(email: String, password: String) async throws {
        guard password.count >= 12 else { throw FinanceError.invalid("Usa una contraseña de al menos 12 caracteres.") }
        let _: SignupResponse = try await request(path: "auth/v1/signup", body: ["email": email, "password": password], token: nil)
    }
    public func changePassword(_ password: String, token: String) async throws {
        guard password.count >= 12 else { throw FinanceError.invalid("Usa una contraseña de al menos 12 caracteres.") }
        let _: FamilyUser = try await request(path: "auth/v1/user", method: "PUT", body: ["password": password], token: token)
    }
    public func logout(_ token: String) async throws {
        let _: EmptyResponse = try await request(path: "auth/v1/logout", query: "scope=local", body: [:], token: token)
    }
    public func list(token: String) async throws -> [FamilyHome] { try await rpc("family_list", body: [:], token: token) }
    public func create(name: String, displayName: String, id: UUID = UUID(), token: String) async throws -> FamilySnapshot { try await rpc("family_create", body: ["p_name": name, "p_display_name": displayName, "p_id": id.uuidString], token: token) }
    public func fetch(home: UUID, token: String) async throws -> FamilySnapshot { try await rpc("family_get", body: ["p_home": home.uuidString], token: token) }
    public func commit(home: UUID, operation: FamilyOperation, token: String) async throws -> FamilyReceipt {
        let encoded = try JSONEncoder().encode(operation.snapshot)
        guard encoded.count <= 16 * 1024 * 1024 else { throw FamilyRemoteError.invalidData }
        let snapshot = try JSONSerialization.jsonObject(with: encoded)
        return try await rpc("family_commit", body: ["p_home": home.uuidString, "p_operation": operation.id.uuidString, "p_expected": operation.expectedRevision, "p_snapshot": snapshot], token: token)
    }
    public func invite(home: UUID, email: String, token: String) async throws -> FamilyInvitation { try await rpc("family_invite", body: ["p_home": home.uuidString, "p_email": email], token: token) }
    public func accept(code: String, displayName: String, token: String) async throws -> FamilySnapshot { try await rpc("family_accept", body: ["p_token": code.trimmingCharacters(in: .whitespacesAndNewlines), "p_display_name": displayName], token: token) }
    public func membership(home: UUID, user: UUID, role: Role, active: Bool, token: String) async throws {
        let _: EmptyResponse = try await rpc("family_membership", body: ["p_home": home.uuidString, "p_user": user.uuidString, "p_role": role.rawValue, "p_active": active], token: token)
    }
    public func invitations(home: UUID, token: String) async throws -> [FamilyInvitation] { try await rpc("family_invitations", body: ["p_home": home.uuidString], token: token) }
    public func cancel(home: UUID, invite: UUID, token: String) async throws {
        let _: EmptyResponse = try await rpc("family_cancel_invite", body: ["p_home": home.uuidString, "p_invite": invite.uuidString], token: token)
    }
    private struct EmptyResponse: Decodable {}
    private struct SignupResponse: Decodable { let id: UUID?; let user: FamilyUser? }
    private func rpc<T: Decodable>(_ name: String, body: [String: Any], token: String) async throws -> T { try await request(path: "rest/v1/rpc/" + name, body: body, token: token) }
    private func request<T: Decodable>(path: String, method: String = "POST", query: String? = nil, body: [String: Any], token: String?) async throws -> T {
        var parts = URLComponents(url: configuration.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        parts.percentEncodedQuery = query
        var request = URLRequest(url: parts.url!)
        request.httpMethod = method; request.timeoutInterval = 25
        request.setValue(configuration.publicKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            guard token.count <= 16384, token.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else { throw FamilyRemoteError.authentication }
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, status) = try await transport(request)
        guard (200...299).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            if message == "access_revoked" { throw FamilyRemoteError.accessRevoked }
            if message == "email_unconfirmed" { throw FamilyRemoteError.unconfirmedEmail }
            if message == "last_admin" { throw FamilyRemoteError.lastAdmin }
            if message == "insufficient_unreserved" { throw FamilyRemoteError.insufficientFunds }
            switch status {
            case 400, 422: throw path.hasPrefix("auth/") ? FamilyRemoteError.authentication : FamilyRemoteError.invalidData
            case 401: throw FamilyRemoteError.authentication
            case 403, 404: throw FamilyRemoteError.forbidden
            case 409: throw FamilyRemoteError.conflict
            default: throw FamilyRemoteError.unavailable
            }
        }
        guard data.count <= 64 * 1024 * 1024 else { throw FamilyRemoteError.unavailable }
        do { return try JSONDecoder().decode(T.self, from: data.isEmpty ? Data("{}".utf8) : data) }
        catch { throw FamilyRemoteError.invalidData }
    }
}
