import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

extension SettingsScreen {

    var sourceSection: some View {
        section("Kaynak") {
            SettingsRow(
                icon: "antenna.radiowaves.left.and.right",
                title: viewModel.activePlaylistName ?? "Kaynak seçilmedi",
                detail: viewModel.lastSyncedText
            ) {
                router.push(.playlistManager)
            }

            SettingsRow(icon: "arrow.clockwise", title: "Şimdi güncelle") {
                Task { await viewModel.resyncActivePlaylist() }
            }

            if let install = dependencies.installSampleLibrary {
                NavigationLink {
                    SampleLibrarySettingsScreen(install: install)
                } label: {
                    SettingsRow(
                        icon: "books.vertical",
                        title: "Örnek kütüphane",
                        detail: "Açık lisanslı örnek filmlerle özellikleri keşfet"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sample-library.open")
            }

            if dependencies.sourceHealth != nil {
                NavigationLink {
                    SourceHealthScreen(dependencies: dependencies)
                } label: {
                    SettingsRow(
                        icon: "checkmark.shield",
                        title: "Kaynak kontrolü ve destek raporu",
                        detail: "Katalog bütünlüğünü ve oynatıcı durumunu incele"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("source-health.open")
            }

            if viewModel.playlistCount > 1 {
                Text("\(viewModel.playlistCount) kaynak kayıtlı")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textTertiary)
            }
        }
    }
}
