import Foundation
import OctopusCore
import OctopusDomain

/// M3U / M3U8 playlist çözümleyici.
///
/// Beklenen biçim:
/// ```
/// #EXTM3U
/// #EXTINF:-1 tvg-id="trt1.tr" tvg-name="TRT 1" tvg-logo="http://..." group-title="ULUSAL",TRT 1
/// http://sunucu/live/kullanici/parola/12345.ts
/// ```
///
/// ## Tasarım notları
/// - Satır satır işlenir (`enumerateLines`); 100 binlik listelerde tüm dosyayı
///   diziye açmak belleği ikiye katlardı.
/// - Öznitelikler **elle** ayrıştırılır. Düzenli ifade her satırda çalıştırılsaydı
///   büyük listelerde belirgin yavaşlama olurdu.
/// - Bozuk satır tüm listeyi düşürmez; atlanır ve sayılır.
public enum M3UParser {

    public struct Result: Sendable {
        public let channels: [Channel]
        public let categories: [MediaCategory]
        /// Ayrıştırılamayan giriş sayısı — tanılama için.
        public let skippedCount: Int
    }

    public static func parse(_ text: String, playlistID: Playlist.ID) -> Result {
        var channels: [Channel] = []
        var categoryOrder: [String] = []
        var seenCategories: Set<String> = []
        var skipped = 0

        var pendingInfo: EntryInfo?
        /// `#EXTGRP:` satırı bazı listelerde grubu ayrıca bildirir.
        var pendingGroup: String?

        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            if trimmed.hasPrefix("#EXTINF:") {
                pendingInfo = parseExtInf(trimmed)
                pendingGroup = nil
                return
            }

            if trimmed.hasPrefix("#EXTGRP:") {
                pendingGroup = String(trimmed.dropFirst("#EXTGRP:".count))
                    .trimmingCharacters(in: .whitespaces)
                return
            }

            // Diğer yönerge satırları (#EXTM3U, #EXTVLCOPT…) yok sayılır.
            if trimmed.hasPrefix("#") { return }

            // Yönerge olmayan satır akış adresidir.
            guard let info = pendingInfo else {
                // Başlıksız adres: hangi kanal olduğu bilinemez.
                skipped += 1
                return
            }
            pendingInfo = nil

            guard let url = URL(string: trimmed), url.scheme != nil else {
                skipped += 1
                return
            }

            let groupTitle = info.attributes["group-title"] ?? pendingGroup
            if let groupTitle, !seenCategories.contains(groupTitle) {
                seenCategories.insert(groupTitle)
                categoryOrder.append(groupTitle)
            }

            // M3U'da kalıcı bir akış kimliği yoktur; adresin kendisi kimliktir.
            let streamKey = trimmed
            let displayName = info.name
                ?? info.attributes["tvg-name"]
                ?? url.lastPathComponent

            channels.append(
                Channel(
                    id: EntityID.channel(playlistID: playlistID, rawID: streamKey),
                    playlistID: playlistID,
                    name: displayName,
                    streamKey: streamKey,
                    logoURL: info.attributes["tvg-logo"].flatMap { URL(string: $0) },
                    categoryID: groupTitle.map {
                        EntityID.category(playlistID: playlistID, kind: .live, rawID: $0)
                    },
                    epgChannelID: info.attributes["tvg-id"],
                    number: info.attributes["tvg-chno"].flatMap { Int($0) },
                    sortOrder: channels.count,
                    isAdult: false
                )
            )
        }

        let categories = categoryOrder.enumerated().map { index, title in
            MediaCategory(
                id: EntityID.category(playlistID: playlistID, kind: .live, rawID: title),
                playlistID: playlistID,
                kind: .live,
                name: title,
                sortOrder: index
            )
        }

        if skipped > 0 {
            Log.parser.warning("M3U: \(skipped) giriş ayrıştırılamadı")
        }

        return Result(channels: channels, categories: categories, skippedCount: skipped)
    }

    // MARK: - #EXTINF ayrıştırma

    private struct EntryInfo {
        var attributes: [String: String]
        var name: String?
    }

    /// `#EXTINF:-1 tvg-id="x" group-title="Spor, Yerel",Kanal Adı`
    ///
    /// ⚠️ Görünen ad **tırnak dışındaki son virgülden** sonra başlar.
    /// Basitçe ilk virgüle bakmak, öznitelik değerindeki virgülde kırılır.
    private static func parseExtInf(_ line: String) -> EntryInfo {
        let body = String(line.dropFirst("#EXTINF:".count))

        var insideQuotes = false
        var separatorIndex: String.Index?

        var index = body.startIndex
        while index < body.endIndex {
            let character = body[index]
            if character == "\"" {
                insideQuotes.toggle()
            } else if character == "," && !insideQuotes {
                separatorIndex = index
            }
            index = body.index(after: index)
        }

        let attributePart: Substring
        let namePart: String?

        if let separatorIndex {
            attributePart = body[body.startIndex..<separatorIndex]
            let rawName = body[body.index(after: separatorIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            namePart = rawName.isEmpty ? nil : rawName
        } else {
            attributePart = body[...]
            namePart = nil
        }

        return EntryInfo(
            attributes: parseAttributes(attributePart),
            name: namePart
        )
    }

    /// `key="value"` çiftlerini elle okur.
    private static func parseAttributes(_ text: Substring) -> [String: String] {
        var attributes: [String: String] = [:]
        var index = text.startIndex

        while index < text.endIndex {
            // Anahtarın başına git.
            guard let equalsIndex = text[index...].firstIndex(of: "=") else { break }

            // Anahtar: eşittirden geriye doğru boşluğa kadar.
            var keyStart = equalsIndex
            while keyStart > text.startIndex {
                let previous = text.index(before: keyStart)
                if text[previous] == " " { break }
                keyStart = previous
            }
            let key = String(text[keyStart..<equalsIndex])

            // Değer: tırnak içinde.
            let afterEquals = text.index(after: equalsIndex)
            guard afterEquals < text.endIndex, text[afterEquals] == "\"" else {
                index = afterEquals
                continue
            }
            let valueStart = text.index(after: afterEquals)
            guard let valueEnd = text[valueStart...].firstIndex(of: "\"") else { break }

            let value = String(text[valueStart..<valueEnd])
            if !key.isEmpty, !value.isEmpty {
                attributes[key] = value
            }
            index = text.index(after: valueEnd)
        }

        return attributes
    }
}
