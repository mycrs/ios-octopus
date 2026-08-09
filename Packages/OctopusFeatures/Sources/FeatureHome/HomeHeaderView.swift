import SwiftUI
import OctopusDesignSystem

/// Ana sayfanın tepesi: marka, saat, karşılama ve abonelik durumu.
///
/// ## Referansla ilişkisi
/// Referans uygulamada tepede logo + kaynak adı, altında karşılama kartı
/// ve iki bilgi kutusu (kullanıcı adı, abonelik) vardı. Buradaki yerleşim
/// aynı bilgiyi taşıyor; **dönen tanıtım afişi kaldırıldı** — ana sayfanın
/// tepesi "neredeyim, hesabım ne durumda" sorusunu cevaplamalı, içerik
/// zaten altındaki raflarda.
///
/// ## iOS'a çevrilirken değişenler
/// - Mor gradyan yerine **markanın vurgu rengi**: kullanıcı Ayarlar'dan
///   rengi değiştirdiğinde burası da onunla değişir, uygulama tek parça durur.
/// - Kutu içinde kutu yok: iki bilgi yan yana, eşit ağırlıkta.
/// - Renk yalnızca **aciliyet** taşır (abonelik bitmek üzereyse turuncu,
///   bittiyse kırmızı). Her zaman renkli bir rozet, gerçek uyarıyı görünmez kılar.
struct HomeHeaderView: View {

    let account: HomeAccount?
    let greeting: String
    /// Bayi adı (panelden gelir); yoksa uygulamanın kendi adı yazılır.
    let brandName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            topRow
            greetingBlock
            if let account, account.hasContent {
                infoTiles(account)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        // Kenara yapışık değil: bu bir **bilgi kartı**, sinematik bir
        // görsel değil. Kenar boşluğu onu raflardan ayırıyor.
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: - Üst satır: marka + saat

    private var topRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(brandName ?? "OCTOPUS")
                    .font(Theme.Typography.rowTitle.weight(.heavy))
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(1)

                if let source = account?.sourceName {
                    Text(source)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Palette.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Theme.Spacing.sm)

            clock
        }
    }

    /// Canlı saat.
    ///
    /// ⚠️ `TimelineView` kullanılıyor, `Timer` + `@State` değil: sayfa
    /// görünmediğinde sistem güncellemeyi kendiliğinden durduruyor.
    /// Elle kurulan bir zamanlayıcı arka planda dönmeye devam ederdi.
    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(context.date, format: .dateTime.hour().minute())
                .font(Theme.Typography.sectionTitle.weight(.semibold))
                .foregroundColor(Theme.Palette.textPrimary)
                .monospacedDigit()
        }
        .accessibilityLabel("Saat")
    }

    // MARK: - Karşılama

    /// ⚠️ Kullanıcı adı burada **tekrar edilmiyor**: alttaki bilgi
    /// kutusunda zaten yazıyor. İki yerde görünce kart özensiz duruyordu.
    private var greetingBlock: some View {
        Text(greeting)
            .font(Theme.Typography.screenTitle)
            .foregroundColor(Theme.Palette.textPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }

    // MARK: - Bilgi kutuları

    /// İki kutu yan yana.
    ///
    /// ⚠️ Sol kutu abonelik bitişi; **bilinmiyorsa** yerini son
    /// güncelleme alıyor. Tek kutu kalınca kart ortada boşluk bırakıyordu
    /// ve M3U kaynaklarda abonelik kavramı hiç yok — o durumda da elde
    /// gerçek bir bilgi kalsın.
    private func infoTiles(_ account: HomeAccount) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let date = account.expiryDateText {
                tile(
                    caption: "ABONELİK BİTİŞİ",
                    value: date,
                    detail: account.expiryText,
                    tint: tint(for: account.urgency)
                )
            } else if let synced = account.lastSyncedText {
                tile(
                    caption: "SON GÜNCELLEME",
                    value: synced,
                    detail: nil,
                    tint: Theme.Palette.textPrimary
                )
            }

            if let username = account.username {
                tile(
                    caption: "KULLANICI",
                    value: username,
                    detail: nil,
                    tint: Theme.Palette.textPrimary
                )
            }
        }
    }

    private func tile(
        caption: String,
        value: String,
        detail: String?,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(caption)
                .font(Theme.Typography.badge)
                .kerning(0.8)
                .foregroundColor(Theme.Palette.textTertiary)

            Text(value)
                .font(Theme.Typography.rowTitle)
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let detail {
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundColor(tint.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.sm)
        .background(Theme.Palette.background.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    private func tint(for urgency: HomeAccount.Urgency) -> Color {
        switch urgency {
        case .normal: return Theme.Palette.textPrimary
        case .soon: return Theme.Palette.warning
        case .expired: return Theme.Palette.error
        }
    }

    /// Kartın zemini: markanın vurgu rengiyle çok hafif bir degrade.
    ///
    /// ⚠️ Doygun bir renk **kasıtlı olarak yok**: kart tüm sayfanın
    /// tepesinde duruyor ve altındaki afişlerle yarışmamalı.
    private var background: some View {
        LinearGradient(
            colors: [
                Theme.Palette.accentMuted,
                Theme.Palette.surface
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
