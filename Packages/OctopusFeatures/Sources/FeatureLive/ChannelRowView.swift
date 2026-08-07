import SwiftUI
import OctopusDomain
import OctopusDesignSystem

/// Tek kanal satırı.
///
/// Referanstaki TV kartının telefon karşılığı: numara, ad, o an yayında
/// olan program ve kalan süre. TV sürümünde bunlar geniş bir yan panelde
/// duruyordu; burada tek satıra sığması gerekiyor.
struct ChannelRowView: View {

    let channel: Channel
    let program: EPGProgram?
    let clock: Date
    let isFavorite: Bool
    let onTap: () -> Void
    let onToggleFavorite: () -> Void
    let onShowGuide: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                ChannelLogoView(url: channel.logoURL)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    HStack(spacing: Theme.Spacing.sm) {
                        // Kanal numarası her zaman görünür: kullanıcılar
                        // kanalları numarayla hatırlıyor ve yayın akışı
                        // olsun olmasın numara aynı yerde durmalı.
                        if let number = channel.number {
                            Text("\(number)")
                                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                .foregroundColor(Theme.Palette.textTertiary)
                                .frame(minWidth: 26, alignment: .trailing)
                        }

                        Text(channel.name)
                            .font(Theme.Typography.rowTitle)
                            .foregroundColor(Theme.Palette.textPrimary)
                            .lineLimit(1)
                    }

                    if let program {
                        programLine(program)
                    } else {
                        // ⚠️ Boş bırakmak yerine sebebi yazılıyor: bazı
                        // kanalların rehberi sunucuda gerçekten yok, veri
                        // uydurmak yanıltıcı olur.
                        Text("Yayın akışı yok")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Palette.textTertiary)
                    }
                }

                Spacer(minLength: 0)

                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(
                            isFavorite ? Theme.Palette.live : Theme.Palette.textTertiary
                        )
                        // Dokunma hedefi ikondan büyük: 17pt'lik bir kalbe
                        // isabet ettirmek zor ve yanlışlıkla satır açılıyordu.
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Satır tek bir öğe olarak okunuyor; bu düğme onun içinde
                // kaybolmasın diye erişilebilirlikten çıkarılıp aşağıda
                // özel eylem olarak sunuluyor.
                .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        // ⚠️ VoiceOver: satır **tek** öğe olarak okunur (numara, ad, program
        // ardı ardına), favori ve rehber ise özel eylem olarak sunulur.
        // İç içe düğme bırakmak, kullanıcıyı her satırda üç kez durduruyordu.
        .accessibilityElement(children: .combine)
        .accessibilityAction(
            named: isFavorite ? "Favorilerden çıkar" : "Favorilere ekle",
            onToggleFavorite
        )
        .accessibilityAction(named: "Yayın akışı", onShowGuide)
        .contextMenu {
            // Rehber uzun basmada: satırda ikinci bir düğme dokunma
            // hedeflerini daraltıyordu.
            Button(action: onShowGuide) {
                Label("Yayın akışı", systemImage: "calendar")
            }
            Button(action: onToggleFavorite) {
                Label(
                    isFavorite ? "Favorilerden çıkar" : "Favorilere ekle",
                    systemImage: isFavorite ? "heart.slash" : "heart"
                )
            }
        }
    }

    /// O an yayında olan program: ad, kalan süre ve ilerleme.
    private func programLine(_ program: EPGProgram) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(program.title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textSecondary)
                    .lineLimit(1)

                if let remaining = LiveChannelsViewModel.remainingText(program, at: clock) {
                    Text(remaining)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Palette.accent)
                        .lineLimit(1)
                        // Program adı uzunsa kalan süre kırpılmasın:
                        // asıl bilgi "daha ne kadar var".
                        .layoutPriority(1)
                }
            }

            ProgressView(value: program.progress(at: clock))
                .progressViewStyle(.linear)
                .tint(Theme.Palette.accent)
                .frame(height: 2)
        }
    }
}
