import SwiftUI
import OctopusDomain
import OctopusDesignSystem

/// Canlı TV ekranının tepesindeki "kaldığın kanal" kartı.
///
/// ## Referansla ilişkisi
/// Referans projede video oynatıcı Canlı TV ekranının **tepesinde her
/// zaman gömülü** duruyordu; kullanıcı kanal listesinde gezinirken de
/// görmeye devam ediyordu. Bizim mimarimizde `FeaturePlayer` ayrı bir
/// modül ve feature'lar birbirini import edemez (bkz. CLAUDE.md demir
/// kural 3) — video gömülemez. Gerçek oynatıcı motoru da Faz 5'te,
/// gerçek cihaz bekliyor.
///
/// Bu kart aynı hissi mimariyi bozmadan veriyor: son izlenen kanalı
/// büyük bir önizleme olarak gösterir, dokunulduğunda gerçek oynatıcıya
/// (şu an ön kontrol ekranına) götürür.
struct LiveNowPlayingCard: View {

    let channel: Channel
    let program: EPGProgram?
    let onTap: () -> Void

    private let height: CGFloat = 180

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                backdrop
                scrim
                info
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Oynatıcıyı açar")
        // Kart dekoratif bir önizleme; erişilebilirlik yazı boyutunda
        // sabit yükseklik taşmasın diye (bkz. FeaturedHeroView'daki aynı tuzak).
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var backdrop: some View {
        // ⚠️ Kareyle görüldü: logosu olmayan kanalda (M3U'da sık rastlanır)
        // yer tutucu düz renk olduğunda kart tamamen boş görünüyordu.
        // ChannelLogoView'ın kullandığı "tv" ikonu buraya da eklendi.
        RemoteImageView(url: channel.logoURL, contentMode: .fit, targetWidth: 320) {
            ZStack {
                Theme.Palette.surfaceElevated
                Image(systemName: "tv")
                    .font(.system(size: 40))
                    .foregroundColor(Theme.Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Theme.Palette.surface)
        .clipped()
    }

    private var scrim: some View {
        LinearGradient(
            colors: [.black.opacity(0.1), .black.opacity(0.75)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Circle()
                    .fill(Theme.Palette.live)
                    .frame(width: 6, height: 6)
                Text("KALDIĞIN KANAL")
                    .font(Theme.Typography.badge)
                    .kerning(1.5)
                    .foregroundColor(.white.opacity(0.85))
            }

            Text(channel.name)
                .font(Theme.Typography.sectionTitle)
                .foregroundColor(.white)
                .lineLimit(1)

            if let program {
                Text(program.title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .padding(Theme.Spacing.md)
    }
}
