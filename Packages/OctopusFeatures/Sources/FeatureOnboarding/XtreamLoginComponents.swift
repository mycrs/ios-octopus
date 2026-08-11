import SwiftUI
import OctopusDesignSystem

struct XtreamLoginModePicker: View {
    @Binding var selection: AddPlaylistViewModel.XtreamLoginMode

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(AddPlaylistViewModel.XtreamLoginMode.allCases) { mode in
                modeButton(mode)
            }
        }
        .padding(Theme.Spacing.xs)
        .background(Theme.Palette.surfaceElevated.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(Theme.Palette.separator.opacity(0.8), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Xtream giriş yöntemi")
    }

    private func modeButton(_ mode: AddPlaylistViewModel.XtreamLoginMode) -> some View {
        let isSelected = selection == mode

        return Button {
            guard selection != mode else { return }
            Haptics.selection()
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = mode
            }
        } label: {
            Label(mode.title, systemImage: mode.icon)
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundColor(isSelected ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(isSelected ? Theme.Palette.accentMuted : .clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private extension AddPlaylistViewModel.XtreamLoginMode {
    var icon: String {
        switch self {
        case .dns: return "network"
        case .resellerCode: return "person.badge.key.fill"
        }
    }
}
