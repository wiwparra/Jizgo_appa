import Foundation
import Security
import HogarCore

enum FamilyCredentials {
    private static func query(_ host: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "HogarFinanzas.Supabase." + host, kSecAttrAccount as String: "session"]
    }
    static func load(host: String) throws -> FamilySession? {
        var parameters = query(host)
        parameters[kSecReturnData as String] = true
        parameters[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(parameters as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw FinanceError.invalid("No se puede abrir la sesión del llavero. Desbloquea el dispositivo e inténtalo otra vez.") }
        return try JSONDecoder().decode(FamilySession.self, from: data)
    }
    static func save(_ session: FamilySession, host: String) throws {
        let data = try JSONEncoder().encode(session)
        let key = query(host)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var parameters = key
            parameters.merge(attributes) { _, new in new }
            status = SecItemAdd(parameters as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw FinanceError.invalid("No se ha podido guardar la sesión en el llavero. No se enviarán cambios hasta resolverlo.") }
    }
    static func delete(host: String) throws {
        let status = SecItemDelete(query(host) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw FinanceError.invalid("No se ha podido borrar la sesión del llavero.") }
    }
}
