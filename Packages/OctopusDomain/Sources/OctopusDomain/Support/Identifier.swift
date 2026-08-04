import Foundation

/// Tip-güvenli kimlik.
///
/// `Identifier<Channel>` ile `Identifier<Movie>` farklı tiplerdir; yanlışlıkla
/// bir film kimliğini kanal fonksiyonuna geçiremezsin — derleyici engeller.
/// Düz `String` kullanmanın sessiz hatalarını baştan yok eder.
public struct Identifier<Subject>: Hashable, Codable, CustomStringConvertible {

    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        value = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public var description: String { value }
}

extension Identifier: Sendable {}

extension Identifier: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}
