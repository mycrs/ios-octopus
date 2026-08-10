import SwiftUI

final class PlayerHostedOverlayStore<Content: View>: ObservableObject {
    struct Snapshot {
        let content: Content
        let brandColor: Color
    }

    @Published private(set) var snapshot: Snapshot

    init(content: Content, brandColor: Color) {
        snapshot = Snapshot(content: content, brandColor: brandColor)
    }

    func update(content: Content, brandColor: Color) {
        snapshot = Snapshot(content: content, brandColor: brandColor)
    }
}

/// Hosting controller'ın root'u sabit kalır. VOD zamanı güncellendiğinde
/// yalnızca store yayın yapar; UIKit/SwiftUI render kimliği yeniden kurulmaz.
struct PlayerHostedOverlay<Content: View>: View {
    @ObservedObject var store: PlayerHostedOverlayStore<Content>

    var body: some View {
        store.snapshot.content
            .environment(\.brandColor, store.snapshot.brandColor)
            .preferredColorScheme(.dark)
    }
}
