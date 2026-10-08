import Foundation

/// Bölüm adresi panel verisini izler; eksik uzantı için medya türü tahmin etmez.
enum XtreamEpisodeURLPolicy {
    static func directURL(_ value: String?) -> URL? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    static func containerExtension(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "." }).lowercased()
        guard (1...10).contains(normalized.utf8.count),
              normalized.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) })
        else { return nil }
        return normalized
    }
}
