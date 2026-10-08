import SwiftUI

@MainActor
final class PlayerHostedOverlayStore<Content: View>: ObservableObject {
    struct Snapshot {
        let content: Content
        let brandColor: Color
    }

    @Published private(set) var snapshot: Snapshot
    private var pendingSnapshot: Snapshot?
    private var updateTask: Task<Void, Never>?

    init(content: Content, brandColor: Color) {
        snapshot = Snapshot(content: content, brandColor: brandColor)
    }

    func update(content: Content, brandColor: Color) {
        pendingSnapshot = Snapshot(content: content, brandColor: brandColor)
        guard updateTask == nil else { return }
        // updateUIViewController içinden senkron @Published yazmak,
        // sürmekte olan SwiftUI çizimini tekrar tetikler.
        updateTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, let next = self.pendingSnapshot else { return }
            self.pendingSnapshot = nil
            self.updateTask = nil
            self.snapshot = next
        }
    }

    func cancelPendingUpdate() {
        updateTask?.cancel()
        updateTask = nil
        pendingSnapshot = nil
    }
}

/// Hosting controller'ın root'u sabit kalır. VOD zamanı güncellendiğinde
/// yalnızca store yayın yapar; UIKit/SwiftUI render kimliği yeniden kurulmaz.
@MainActor
struct PlayerHostedOverlay<Content: View>: View {
    @ObservedObject var store: PlayerHostedOverlayStore<Content>

    var body: some View {
        store.snapshot.content
            .environment(\.brandColor, store.snapshot.brandColor)
            .preferredColorScheme(.dark)
    }
}
