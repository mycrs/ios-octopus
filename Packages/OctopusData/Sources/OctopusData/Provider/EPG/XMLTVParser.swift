import Foundation
import OctopusCore
import OctopusDomain

/// XMLTV elektronik program rehberi çözümleyici.
///
/// Beklenen biçim:
/// ```xml
/// <tv>
///   <programme start="20260804120000 +0300" stop="20260804130000 +0300" channel="trt1.tr">
///     <title lang="tr">Haberler</title>
///     <desc lang="tr">Günün haberleri</desc>
///   </programme>
/// </tv>
/// ```
///
/// ## Neden akış halinde?
/// 14.000 kanallı bir hesapta XMLTV dosyası yüzlerce megabayt olabilir ve
/// tek seferde belleğe alınmış program dizisi uygulamayı düşürür.
/// Bu çözümleyici programları **parçalar hâlinde** teslim eder; çağıran
/// her parçayı veritabanına yazıp bırakır.
///
/// İptal desteklenir: kullanıcı senkronizasyonu durdurduğunda çözümleme de durur.
public final class XMLTVParser: NSObject {

    /// Bir parçadaki program sayısı. Veritabanına tek işlemde yazılacak miktar.
    public static let defaultChunkSize = 2_000

    private let chunkSize: Int
    private let onChunk: ([EPGProgram]) throws -> Void

    private var buffer: [EPGProgram] = []
    private var totalCount = 0
    private var skippedCount = 0
    private var deliveryError: Error?

    // Çözümleme sırasındaki geçici durum
    private var currentChannelID: String?
    private var currentStart: Date?
    private var currentStop: Date?
    private var currentTitle: String?
    private var currentDescription: String?
    private var activeElement: String?
    private var textBuffer = ""

    private init(chunkSize: Int, onChunk: @escaping ([EPGProgram]) throws -> Void) {
        self.chunkSize = chunkSize
        self.onChunk = onChunk
    }

    /// - Parameter onChunk: Her parça için çağrılır. Fırlatırsa çözümleme durur.
    /// - Returns: Çözümlenen toplam program sayısı.
    /// - Throws: `CancellationError` iptal edildiğinde, `AppError.invalidResponse`
    ///   XML bozuksa.
    @discardableResult
    public static func parse(
        data: Data,
        chunkSize: Int = XMLTVParser.defaultChunkSize,
        onChunk: @escaping ([EPGProgram]) throws -> Void
    ) throws -> Int {
        let handler = XMLTVParser(chunkSize: chunkSize, onChunk: onChunk)

        let parser = XMLParser(data: data)
        parser.delegate = handler
        parser.shouldProcessNamespaces = false

        let succeeded = parser.parse()

        // Teslim sırasında oluşan hata (iptal dahil) XML hatasından önce gelir.
        if let deliveryError = handler.deliveryError {
            throw deliveryError
        }

        guard succeeded else {
            let reason = parser.parserError?.localizedDescription ?? "bilinmeyen"
            Log.parser.error("XMLTV çözümlenemedi: \(reason)")
            throw AppError.invalidResponse(reason: "EPG dosyası okunamadı")
        }

        // Son parça
        try handler.flush()

        if handler.skippedCount > 0 {
            Log.parser.warning("XMLTV: \(handler.skippedCount) program eksik alan yüzünden atlandı")
        }
        Log.parser.info("XMLTV: \(handler.totalCount) program çözümlendi")

        return handler.totalCount
    }

    private func flush() throws {
        guard !buffer.isEmpty else { return }
        try onChunk(buffer)
        buffer.removeAll(keepingCapacity: true)
    }
}

// MARK: - XMLParserDelegate

extension XMLTVParser: XMLParserDelegate {

    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        // Kullanıcı senkronizasyonu durdurduysa çözümlemeyi sürdürmenin anlamı yok.
        if Task.isCancelled {
            deliveryError = CancellationError()
            parser.abortParsing()
            return
        }

        activeElement = elementName
        textBuffer = ""

        guard elementName == "programme" else { return }

        currentChannelID = attributes["channel"]
        currentStart = XMLTVDate.parse(attributes["start"])
        currentStop = XMLTVDate.parse(attributes["stop"])
        currentTitle = nil
        currentDescription = nil
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    public func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        textBuffer = ""

        switch elementName {
        case "title":
            // Çok dilli rehberlerde ilk başlık kullanılır.
            if currentTitle == nil, !text.isEmpty { currentTitle = text }
        case "desc":
            if currentDescription == nil, !text.isEmpty { currentDescription = text }
        case "programme":
            appendCurrentProgram(parser)
        default:
            break
        }

        activeElement = nil
    }

    private func appendCurrentProgram(_ parser: XMLParser) {
        defer {
            currentChannelID = nil
            currentStart = nil
            currentStop = nil
            currentTitle = nil
            currentDescription = nil
        }

        // Kanal, başlangıç ve bitiş olmadan program rehberde gösterilemez.
        guard let channelID = currentChannelID,
              let start = currentStart,
              let stop = currentStop,
              stop > start
        else {
            skippedCount += 1
            return
        }

        let program = EPGProgram(
            id: EntityID.epgProgram(epgChannelID: channelID, startDate: start),
            epgChannelID: channelID,
            title: currentTitle ?? "—",
            summary: currentDescription,
            startDate: start,
            endDate: stop
        )

        buffer.append(program)
        totalCount += 1

        guard buffer.count >= chunkSize else { return }
        do {
            try flush()
        } catch {
            // Delegate metotları fırlatamaz; hata saklanıp çözümleme durdurulur.
            deliveryError = error
            parser.abortParsing()
        }
    }
}

// MARK: - Zaman biçimi

/// XMLTV zaman damgaları: `20260804120000 +0300` veya `20260804120000`.
enum XMLTVDate {

    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 14 else { return nil }

        if trimmed.count > 14 {
            if let date = withOffset.date(from: trimmed) { return date }
        }
        // Saat dilimi bildirilmemişse UTC varsayılır — XMLTV önerisi budur.
        return withoutOffset.date(from: String(trimmed.prefix(14)))
    }

    private static let withOffset: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMddHHmmss Z"
        return formatter
    }()

    private static let withoutOffset: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter
    }()
}
