import SwiftUI

/// Uzak logo veya afiş bulunamadığında markaya uyumlu, içerikten türetilen görsel.
public struct MediaArtworkPlaceholder: View {
    private let title: String?
    private let symbol: String
    private let compact: Bool

    @Environment(\.brandColor) private var brandColor

    public init(title: String?, symbol: String, compact: Bool = false) {
        self.title = title
        self.symbol = symbol
        self.compact = compact
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [brandColor.opacity(0.34), Theme.Palette.surfaceElevated],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(brandColor.opacity(0.14))
                .scaleEffect(1.35)
                .offset(x: compact ? 18 : 42, y: compact ? -18 : -58)

            VStack(spacing: compact ? 2 : Theme.Spacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 13 : 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))

                if let initials {
                    Text(initials)
                        .font(.system(size: compact ? 13 : 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
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
