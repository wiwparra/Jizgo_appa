import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct Backup: Codable, Sendable {
    public let format: String
    public let version: Int
    public let created: Date
    public let household: Household
    public init(household: Household) { format = "HogarFinanzas"; version = 1; created = Date(); self.household = household }
    public static func decode(_ data: Data) throws -> Household {
        guard data.count <= 64 * 1024 * 1024 else { throw FinanceError.corrupt }
        do {
            let backup = try JSONDecoder().decode(Backup.self, from: data)
            guard backup.format == "HogarFinanzas", backup.version == 1 else { throw FinanceError.corrupt }
            try backup.household.validate()
            return backup.household
        } catch { throw FinanceError.corrupt }
    }
    public func encoded() throws -> Data {
        try household.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= 64 * 1024 * 1024 else { throw FinanceError.invalid("El archivo supera el límite de 64 MB. No se han reemplazado los datos.") }
        return data
    }
}

/// Una instancia por archivo. Solo AppStore (MainActor) accede al repositorio de la aplicación.
/// Escritura atómica, permisos 0600, validación previa y ninguna recuperación destructiva automática.
public final class LocalRepository {
    public let url: URL
    private var writable = false
    public init(url: URL) { self.url = url }
    public func load() throws -> Household? {
        writable = false
        guard FileManager.default.fileExists(atPath: url.path) else { writable = true; return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= 64 * 1024 * 1024 else { throw FinanceError.corrupt }
        let result = try Backup.decode(Data(contentsOf: url))
        writable = true
        return result
    }
    public func save(_ household: Household) throws {
        guard writable else { throw FinanceError.invalid("Almacenamiento bloqueado: resuelve el error de lectura antes de guardar.") }
        let data = try Backup(household: household).encoded()
        try ProtectedFile.write(data, to: url)
    }
    public func restore(_ data: Data, confirmed: Bool) throws -> Household {
        guard confirmed else { throw FinanceError.confirmationRequired }
        let household = try Backup.decode(data)
        // Una copia válida y confirmada es la única recuperación que desbloquea un archivo ilegible.
        let oldWritable = writable
        writable = true
        do { try save(household); return household }
        catch { writable = oldWritable; throw error }
    }
}

// Compartido por el hogar local y la cola familiar: permisos antes de publicar el archivo por rename atómico.
public enum ProtectedFile {
    public static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".hogar-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        defer { try? FileManager.default.removeItem(at: temporary) }
        #if os(iOS)
        try data.write(to: temporary, options: .completeFileProtection)
        #else
        try data.write(to: temporary)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        let result = temporary.withUnsafeFileSystemRepresentation { source in
            url.withUnsafeFileSystemRepresentation { destination in rename(source!, destination!) }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
