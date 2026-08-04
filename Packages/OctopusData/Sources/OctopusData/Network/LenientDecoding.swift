import Foundation

/// Tip tutarsızlığına dayanıklı kod çözme.
///
/// ## Neden gerekli?
/// Xtream Codes panelleri sürüme ve kuruluma göre aynı alanı farklı tiplerde
/// döndürür:
/// - `"stream_id": 12345` **veya** `"stream_id": "12345"`
/// - `"rating": 7.5` **veya** `"rating": "7.5"` **veya** `"rating": ""`
/// - `"tv_archive": 0` **veya** `"tv_archive": "0"`
///
/// Katı `Decodable` kullanılsaydı tek bir tutarsız alan **tüm kanal listesini**
/// düşürürdü. Kullanıcı 14.000 kanal yerine boş ekran görürdü ve sebebi
/// anlaşılmazdı.
///
/// Bu sarmalayıcı değeri çözemezse `nil` verir; liste ayakta kalır.
@propertyWrapper
struct Lenient<Value: LenientlyDecodable>: Decodable {

    var wrappedValue: Value?

    init(wrappedValue: Value?) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.singleValueContainer() else {
            wrappedValue = nil
            return
        }
        wrappedValue = Value.decodeLeniently(from: container)
    }
}

extension Lenient: Equatable where Value: Equatable {}

/// Farklı JSON gösterimlerinden okunabilen tip.
protocol LenientlyDecodable {
    static func decodeLeniently(from container: SingleValueDecodingContainer) -> Self?
}

extension Int: LenientlyDecodable {
    static func decodeLeniently(from container: SingleValueDecodingContainer) -> Int? {
        if let value = try? container.decode(Int.self) { return value }
        if let text = try? container.decode(String.self) {
            // "12345" veya "1600000000" (epoch dizgisi)
            if let value = Int(text) { return value }
            // "7.0" gibi ondalık dizgiler
            if let value = Double(text) { return Int(value) }
            return nil
        }
        if let value = try? container.decode(Double.self) { return Int(value) }
        return nil
    }
}

extension Double: LenientlyDecodable {
    static func decodeLeniently(from container: SingleValueDecodingContainer) -> Double? {
        if let value = try? container.decode(Double.self) { return value }
        if let text = try? container.decode(String.self) { return Double(text) }
        if let value = try? container.decode(Int.self) { return Double(value) }
        return nil
    }
}

extension String: LenientlyDecodable {
    static func decodeLeniently(from container: SingleValueDecodingContainer) -> String? {
        if let value = try? container.decode(String.self) {
            // Panellerin boş alanı "" veya "null" olarak döndürmesi yaygın.
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed.isEmpty || trimmed.lowercased() == "null") ? nil : trimmed
        }
        if let value = try? container.decode(Int.self) { return String(value) }
        if let value = try? container.decode(Double.self) { return String(value) }
        return nil
    }
}

extension Bool: LenientlyDecodable {
    static func decodeLeniently(from container: SingleValueDecodingContainer) -> Bool? {
        if let value = try? container.decode(Bool.self) { return value }
        if let value = try? container.decode(Int.self) { return value != 0 }
        if let text = try? container.decode(String.self) {
            switch text.lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no": return false
            default: return nil
            }
        }
        return nil
    }
}

// Alan JSON'da hiç yoksa da hata verilmemeli: eksik anahtar `nil` sayılır.
extension KeyedDecodingContainer {
    func decode<T>(_ type: Lenient<T>.Type, forKey key: Key) throws -> Lenient<T> {
        try decodeIfPresent(type, forKey: key) ?? Lenient(wrappedValue: nil)
    }
}

// MARK: - Xtream zaman biçimleri

enum XtreamDate {

    /// Xtream tarihleri epoch saniyesi olarak döner — çoğu zaman dizgi hâlinde.
    static func fromEpoch(_ value: Int?) -> Date? {
        guard let value, value > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(value))
    }

    /// `releaseDate` alanı "2020-05-17" biçimindedir.
    static func fromDayString(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return dayFormatter.date(from: value)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
