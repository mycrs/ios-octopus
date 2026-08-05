import Foundation

/// Elektronik program rehberi kaydı.
public struct EPGProgram: Identifiable, Hashable, Codable, Sendable {

    public typealias ID = Identifier<EPGProgram>

    public let id: ID

    /// XMLTV `channel` alanı — `Channel.epgChannelID` ile eşleşir.
    public let epgChannelID: String

    public var title: String
    public var summary: String?
    public var startDate: Date
    public var endDate: Date

    public init(
        id: ID,
        epgChannelID: String,
        title: String,
        summary: String? = nil,
        startDate: Date,
        endDate: Date
    ) {
        self.id = id
        self.epgChannelID = epgChannelID
        self.title = title
        self.summary = summary
        self.startDate = startDate
        self.endDate = endDate
    }

    public var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    /// Verilen anda yayında mı?
    ///
    /// - Not: Domain saf kalsın diye `Date()` **içeride çağrılmaz**;
    ///   zaman dışarıdan verilir. Böylece test edilebilir olur.
    public func isOnAir(at date: Date) -> Bool {
        date >= startDate && date < endDate
    }

    /// Programın ne kadarı geçti (0...1). Yayında değilse sınıra sabitlenir.
    /// Bitmesine kalan süre — geçmişse `nil`.
    ///
    /// Sunum katmanı bunu "32 dk kaldı" diye yazar. Hesap burada:
    /// "kalan süre" bir zaman kuralı, biçimlendirme sunumun işi.
    public func remaining(at date: Date) -> TimeInterval? {
        let left = endDate.timeIntervalSince(date)
        return left > 0 ? left : nil
    }

    public func progress(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        let elapsed = date.timeIntervalSince(startDate)
        return min(max(elapsed / duration, 0), 1)
    }
}
