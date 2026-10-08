import SwiftUI

private struct PlayerControlsPressChangedKey: EnvironmentKey {
    static let defaultValue: (UUID, Bool) -> Void = { _, _ in }
}

extension EnvironmentValues {
    var playerControlsPressChanged: (UUID, Bool) -> Void {
        get { self[PlayerControlsPressChangedKey.self] }
        set { self[PlayerControlsPressChangedKey.self] = newValue }
    }
}

/// Observe the button's own press state without adding another gesture.
struct PlayerControlsPressTracker: ViewModifier {
    let isPressed: Bool
    @State private var id = UUID()
    @Environment(\.playerControlsPressChanged) private var changed

    func body(content: Content) -> some View {
        content
            .onChange(of: isPressed) { changed(id, $0) }
            .onDisappear { changed(id, false) }
    }
}

struct PlayerControlsPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(PlayerControlsPressTracker(isPressed: configuration.isPressed))
    }
}
