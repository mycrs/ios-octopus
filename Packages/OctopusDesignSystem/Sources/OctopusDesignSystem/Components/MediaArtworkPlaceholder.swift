import SwiftUI

/// Uzak logo veya afiş bulunamadığında markaya uyumlu, içerikten türetilen görsel.
public struct MediaArtworkPlaceholder: View {
    private let title: String?
    private let symbol: String
    private let compact: Bool

    public init(title: String?, symbol: String, compact: Bool = false) {
        self.title = title
        self.symbol = symbol
        self.compact = compact
    }

    public var body: some View {
        ZStack {
            Theme.Palette.surfaceElevated

            VStack(spacing: compact ? 2 : Theme.Spacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 13 : 20, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)

                if let initials {
                    Text(initials)
                        .font(.system(size: compact ? 13 : 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var initials: String? {
        let words = title?
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .prefix(2)
            .compactMap(\.first)
        guard let words, !words.isEmpty else { return nil }
        return String(words).uppercased()
    }
}
