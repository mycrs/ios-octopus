import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

public struct LiveDependencies {
    public let channels: ChannelRepository
    public let epg: EPGRepository
    public let favorites: FavoritesRepository

    public init(
        channels: ChannelRepository,
        epg: EPGRepository,
        favorites: FavoritesRepository
    ) {
        self.channels = channels
        self.epg = epg
        self.favorites = favorites
    }
}

/// Canlı TV: kategori listesi → kanal listesi → oynatıcı.
/// Faz 4'te doldurulacak.
///
/// ⚠️ Bu ekran oynatıcıyı doğrudan **açmaz**; `router.presentPlayer(...)` çağırır.
/// `FeaturePlayer`'ı import etmez — bu yüzden ikisi bağımsız derlenir.
public struct LiveScreen: View {

    private let dependencies: LiveDependencies
    @EnvironmentObject private var router: AppRouter

    public init(dependencies: LiveDependencies) {
        self.dependencies = dependencies
    }

    public var body: some View {
        EmptyStateView(
            icon: "tv",
            title: "Canlı TV",
            message: "Kategoriler, kanal listesi ve EPG şeridi Faz 4'te gelecek."
        )
        .background(Theme.Palette.background)
    }
}
