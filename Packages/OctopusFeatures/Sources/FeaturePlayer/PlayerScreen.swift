import SwiftUI
import UIKit          // UIPasteboard
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation
import OctopusPlayback

public struct PlayerDependencies {
    public let resolver: PlaybackEngineResolver
    public let streams: StreamResolving
    public let progress: PlaybackProgressRepository
    public let history: WatchHistoryRepository
    public let channels: ChannelRepository
    public let vod: VODRepository
    public let series: SeriesRepository

    public init(
        resolver: PlaybackEngineResolver,
        streams: StreamResolving,
        progress: PlaybackProgressRepository,
        history: WatchHistoryRepository,
        channels: ChannelRepository,
        vod: VODRepository,
        series: SeriesRepository
    ) {
        self.resolver = resolver
        self.streams = streams
        self.progress = progress
        self.history = history
        self.channels = channels
        self.vod = vod
        self.series = series
    }
}

/// Tam ekran oynatıcı.
///
/// ⚠️ Bu ekran **hangi motorun** çalıştığını bilmez. `PlaybackEngineResolver`
/// karar verir, `PlaybackEngine` protokolü üzerinden kontrol edilir.
/// AVPlayer'dan VLC'ye düşüş burada değil, `PlayerController`'da yönetilir.
/// Faz 5'te doldurulacak.
public struct PlayerScreen: View {

    @StateObject private var viewModel: PlayerPreflightViewModel
    @EnvironmentObject private var router: AppRouter

    @State private var didCopy = false

    public init(presentation: PlayerPresentation, dependencies: PlayerDependencies) {
        _viewModel = StateObject(
            wrappedValue: PlayerPreflightViewModel(
                dependencies: dependencies,
                source: presentation.source
            )
        )
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .task { await viewModel.run() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.outcome {
        case .checking:
            LoadingStateView(message: "Yayın adresi çözülüyor")

        case .failed(let message):
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Yayın adresi alınamadı",
                message: message,
                actionTitle: "Kapat",
                action: { router.dismissPlayer() }
            )

        case .ready(let item):
            readyState(item)
        }
    }

    /// Zincir çalışıyor: adres üretildi, sıra oynatıcıda.
    private func readyState(_ item: PlaybackItem) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44))
                .foregroundColor(Theme.Palette.accent)

            VStack(spacing: Theme.Spacing.xs) {
                Text(item.title)
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                // Format Domain'de ham değer; görünen ad sunum katmanının işi.
                Text("Yayın adresi hazır · \(item.format.rawValue.uppercased())")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textSecondary)
            }

            // Kimlik bilgileri maskeli: ekran görüntüsü hesabı ele vermemeli.
            Text(PlayerPreflightViewModel.maskedURL(item.url))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Theme.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity)
                .background(Theme.Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))

            Text(
                "Oynatıcı motoru henüz eklenmedi (Faz 5, gerçek cihaz gerekiyor). "
                + "Adresi kopyalayıp harici bir oynatıcıda deneyebilirsin — "
                + "açılıyorsa kaynak, senkronizasyon ve adres üretimi çalışıyor demektir."
            )
            .font(Theme.Typography.caption)
            .foregroundColor(Theme.Palette.textSecondary)
            .multilineTextAlignment(.center)

            VStack(spacing: Theme.Spacing.sm) {
                Button {
                    UIPasteboard.general.string = item.url.absoluteString
                    didCopy = true
                } label: {
                    Label(
                        didCopy ? "Kopyalandı" : "Adresi kopyala",
                        systemImage: didCopy ? "checkmark" : "doc.on.doc"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button("Kapat") { router.dismissPlayer() }
                    .foregroundColor(Theme.Palette.textSecondary)
            }
        }
        .padding(Theme.Spacing.xl)
    }
}
