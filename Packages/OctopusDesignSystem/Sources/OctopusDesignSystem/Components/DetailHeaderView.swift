import SwiftUI

/// Detay ekranlarının sinematik başlığı: arka plan görseli + perde + afiş.
///
/// Film ve dizi detayı **aynı** bileşeni kullanır. Ayrı ayrı yazılsaydı
/// ikisi zamanla birbirinden ayrı düşerdi — referans projede tam olarak
/// bu olmuştu (aynı görünüm iki dosyada, biri güncellenip diğeri kalmış).
///
/// ## Perde neden iki katmanlı?
/// Tek bir dikey degrade, açık renkli afişlerde başlığı okunmaz bırakıyor.
/// Alttan yukarı koyulaşan bir perde metni taşır, üstteki ince perde de
/// durum çubuğu ikonlarının görselde kaybolmasını engeller.
public struct DetailHeaderView<Actions: View>: View {

    private let backdropURL: URL?
    private let posterURL: URL?
    private let title: String
    private let subtitle: String?
    private let chips: [DetailChip]
    private let actions: Actions

    /// Arka planın yüksekliği. Afiş bunun alt kenarına biner.
    private let backdropHeight: CGFloat = 220
    private let posterWidth: CGFloat = 108

    public init(
        backdropURL: URL?,
        posterURL: URL?,
        title: String,
        subtitle: String? = nil,
        chips: [DetailChip] = [],
        @ViewBuilder actions: () -> Actions
    ) {
        self.backdropURL = backdropURL
        self.posterURL = posterURL
        self.title = title
        self.subtitle = subtitle
        self.chips = chips
        self.actions = actions()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            backdrop
            titleBlock
            if !chips.isEmpty { chipRow }
            actions.padding(.horizontal, Theme.Spacing.md)
        }
    }

    // MARK: - Arka plan

    private var backdrop: some View {
        // Arka plan yoksa afişin kendisi kullanılır: boş gri dikdörtgen
        // yerine içeriğin kendi rengi görünsün.
        RemoteImageView(url: backdropURL ?? posterURL, contentMode: .fill) {
            Theme.Palette.surfaceElevated
        }
        .frame(maxWidth: .infinity)
        .frame(height: backdropHeight)
        .clipped()
        .overlay(scrim)
        .overlay(alignment: .bottomLeading) {
            PosterView(url: posterURL, width: posterWidth)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                .padding(.horizontal, Theme.Spacing.md)
                .offset(y: posterOverhang)
        }
        // Taşan afişe yer aç; başlık bloğu üstüne binmesin.
        .padding(.bottom, posterOverhang)
    }

    /// Afişin arka planın altına taşan miktarı.
    private var posterOverhang: CGFloat { 36 }

    private var scrim: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Theme.Palette.background.opacity(0),
                    Theme.Palette.background.opacity(0.55),
                    Theme.Palette.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            // Üstteki ince perde: durum çubuğu ikonları görselde kaybolmasın.
            LinearGradient(
                colors: [Theme.Palette.background.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
    }

    // MARK: - Başlık

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(title)
                .font(Theme.Typography.screenTitle)
                .foregroundColor(Theme.Palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(chips) { chip in
                    DetailChipView(chip: chip)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
    }
}

/// Künye çipi: puan, yıl, süre, tür…
///
/// Tek bir uzun metin yerine ayrı çipler: uzun tür listelerinde satır
/// taşması yerine yatay kaydırma olur, göz de bilgileri ayırt eder.
public struct DetailChip: Identifiable, Hashable, Sendable {

    public let id: String
    public let text: String
    public let icon: String?
    /// Puan gibi öne çıkması gereken çipler için.
    public let isHighlighted: Bool

    public init(text: String, icon: String? = nil, isHighlighted: Bool = false) {
        self.id = "\(icon ?? "")-\(text)"
        self.text = text
        self.icon = icon
        self.isHighlighted = isHighlighted
    }
}

private struct DetailChipView: View {

    let chip: DetailChip

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let icon = chip.icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(chip.text)
                .font(Theme.Typography.caption)
                .lineLimit(1)
        }
        .foregroundColor(chip.isHighlighted ? Theme.Palette.warning : Theme.Palette.textSecondary)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            chip.isHighlighted
                ? Theme.Palette.warning.opacity(0.14)
                : Theme.Palette.surface
        )
        .clipShape(Capsule())
    }
}
