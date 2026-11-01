import Foundation

public enum EntryTags {
    public static func parse(_ input: String) throws -> [String] {
        guard input.count <= 1000 else { throw FinanceError.invalid("Las etiquetas son demasiado largas.") }
        var labels: [String] = []
        var seen: Set<String> = []
        for part in input.split(separator: ",", omittingEmptySubsequences: true) {
            let label = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { continue }
            guard label.count <= 32, label.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
                throw FinanceError.invalid("Cada etiqueta admite hasta 32 caracteres, sin saltos de línea.")
            }
            if seen.insert(key(label)).inserted { labels.append(label) }
        }
        guard labels.count <= 10 else { throw FinanceError.invalid("Puedes añadir hasta 10 etiquetas por movimiento.") }
        return labels
    }
    public static func key(_ label: String) -> String {
        // Regla determinista compartida con PostgreSQL: NFD, diacríticos latinos y A–Z.
        let scalars = label.trimmingCharacters(in: .whitespacesAndNewlines).decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { !(0x0300...0x036f).contains($0.value) }
            .map { scalar in (0x41...0x5a).contains(scalar.value) ? UnicodeScalar(scalar.value + 32)! : scalar }
        return String(String.UnicodeScalarView(scalars))
    }
    public static func valid(_ tags: [String]) -> Bool {
        guard tags.count <= 10 else { return false }
        var seen: Set<String> = []
        return tags.allSatisfy { label in
            !label.isEmpty && label.count <= 32 && label == label.trimmingCharacters(in: .whitespacesAndNewlines) &&
            !label.contains(",") && label.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } && seen.insert(key(label)).inserted
        }
    }
}
