import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

/// Kayıtlı kaynakların yönetimi.
public struct PlaylistManagerView: View {

    @StateObject private var viewModel: PlaylistManagerViewModel
    @EnvironmentObject private var router: AppRouter
    @State private var pendingDeletion: PlaylistManagerViewModel.Row?

    public init(dependencies: SettingsDependencies) {
        _viewModel = StateObject(wrappedValue: PlaylistManagerViewModel(dependencies: dependencies))
    }

    public var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()
            content
        }
        .navigationTitle("Kaynaklar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    router.present(.addPlaylist)
                } label: {
                    Image(systemName: "plus")
                }
                .tint(Theme.Palette.accent)
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .confirmationDialog(
            "Bu kaynak silinsin mi?",
            isPresented: .init(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive) {
                if let row = pendingDeletion {
                    Task { await viewModel.delete(row.id) }
                }
                pendingDeletion = nil
            }
            Button("Vazgeç", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Kanallar ve filmler silinir. Favorilerin ve izleme geçmişin korunur.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            LoadingStateView(message: "Kaynaklar yükleniyor")
        } else if viewModel.rows.isEmpty {
            EmptyStateView(
                icon: "antenna.radiowaves.left.and.right",
                title: "Kaynak yok",
                message: "Xtream hesabını veya M3U bağlantını ekleyerek başla.",
                actionTitle: "Kaynak ekle",
                action: { router.present(.addPlaylist) }
            )
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.md) {
                if let errorMessage = viewModel.errorMessage {
                    InlineMessageView(text: errorMessage, kind: .error)
                }

                ForEach(viewModel.rows) { row in
                    PlaylistRowView(
                        row: row,
                        isSyncing: viewModel.syncingID == row.id,
                        onActivate: { Task { await viewModel.activate(row.id) } },
                        onResync: { Task { await viewModel.resync(row.id) } },
                        onDelete: { pendingDeletion = row }
                    )
                }
            }
            .padding(Theme.Spacing.lg)
        }
    }
}

/// Tek kaynak satırı.
private struct PlaylistRowView: View {

    let row: PlaylistManagerViewModel.Row
    let isSyncing: Bool
    let onActivate: () -> Void
    let onResync: () -> Void
    let onDelete: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                if row.isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.Palette.accent)
                        .accessibilityLabel("Aktif kaynak")
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(row.name)
                        .font(Theme.Typography.rowTitle)
                        .foregroundColor(Theme.Palette.textPrimary)
                    Text(AppLocalization.localized(row.detail, locale: locale))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Palette.textSecondary)
                }

                Spacer(minLength: 0)

                if isSyncing {
                    ProgressView().tint(Theme.Palette.accent)
                }
            }

            if let lastSyncedText = row.lastSyncedText {
                Text(AppLocalization.localized(lastSyncedText, locale: locale))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textTertiary)
            }

            HStack(spacing: Theme.Spacing.md) {
                if !row.isActive {
                    Button("Bunu kullan", action: onActivate)
                        .buttonStyle(.bordered)
                        .tint(Theme.Palette.accent)
                }
                Button("Yenile", action: onResync)
                    .buttonStyle(.bordered)
                    .tint(Theme.Palette.textSecondary)
                Spacer(minLength: 0)
                Button("Sil", role: .destructive, action: onDelete)
                    .buttonStyle(.bordered)
                    .tint(Theme.Palette.error)
            }
            .disabled(isSyncing)
            .font(Theme.Typography.caption)
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(
                    row.isActive ? Theme.Palette.accent.opacity(0.5) : Color.clear,
                    lineWidth: 1
                )
        )
    }
}
