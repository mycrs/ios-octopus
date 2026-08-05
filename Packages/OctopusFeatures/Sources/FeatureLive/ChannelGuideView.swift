import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

/// Bir kanalın gün boyu yayın akışı.
public struct ChannelGuideView: View {

    @StateObject private var viewModel: ChannelGuideViewModel
    @EnvironmentObject private var router: AppRouter

    public init(channelID: Channel.ID, dependencies: LiveDependencies) {
        _viewModel = StateObject(
            wrappedValue: ChannelGuideViewModel(channelID: channelID, dependencies: dependencies)
        )
    }

    public var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                dayBar
                content
            }
        }
        .navigationTitle(viewModel.channel?.name ?? "Yayın akışı")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let channel = viewModel.channel {
                    Button {
                        router.presentPlayer(.liveChannel(channel.id))
                    } label: {
                        Image(systemName: "play.circle.fill")
                    }
                    .accessibilityLabel("Kanalı aç")
                }
            }
        }
        .task { await viewModel.load() }
    }

    private var dayBar: some View {
        HStack {
            Button {
                Task { await viewModel.changeDay(by: -1) }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!viewModel.canGoBack)

            Spacer()

            Text(viewModel.dayTitle)
                .font(Theme.Typography.rowTitle)
                .foregroundColor(Theme.Palette.textPrimary)

            Spacer()

            Button {
                Task { await viewModel.changeDay(by: 1) }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!viewModel.canGoForward)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Palette.surface)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView()

        case .failed(let error):
            ErrorStateView(error: error) { Task { await viewModel.load() } }

        case .loaded:
            if viewModel.entries.isEmpty {
                EmptyStateView(
                    icon: "calendar.badge.exclamationmark",
                    title: "Yayın akışı yok",
                    message: viewModel.channel?.epgChannelID == nil
                        ? "Bu kanal için rehber bilgisi sağlanmıyor."
                        : "Bu gün için program bilgisi bulunamadı."
                )
            } else {
                programList
            }
        }
    }

    private var programList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.xs) {
                    ForEach(viewModel.entries) { entry in
                        GuideRow(entry: entry, timeText: viewModel.timeText)
                            .id(entry.id)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .onAppear {
                // Şu an oynayan programa kaydır: kullanıcı listeyi elle
                // aramak zorunda kalmasın.
                if let current = viewModel.entries.first(where: \.isOnAir) {
                    proxy.scrollTo(current.id, anchor: .center)
                }
            }
        }
    }
}

private struct GuideRow: View {

    let entry: ChannelGuideViewModel.Entry
    let timeText: (Date) -> String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Text(timeText(entry.program.startDate))
                .font(Theme.Typography.caption)
                .foregroundColor(
                    entry.isOnAir ? Theme.Palette.accent : Theme.Palette.textTertiary
                )
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(entry.program.title)
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(titleColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let summary = entry.program.summary, !summary.isEmpty {
                    Text(summary)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Palette.textTertiary)
                        .lineLimit(2)
                }

                if let progress = entry.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(Theme.Palette.accent)
                        .frame(height: 2)
                        .padding(.top, Theme.Spacing.xxs)
                }
            }

            Spacer(minLength: 0)

            if entry.isOnAir {
                Text("CANLI")
                    .font(Theme.Typography.badge)
                    .foregroundColor(Theme.Palette.live)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .background(Theme.Palette.live.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(Theme.Spacing.md)
        .background(entry.isOnAir ? Theme.Palette.accentMuted : Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    /// Biten programlar soluk: kullanıcı nerede olduğunu bir bakışta görsün.
    private var titleColor: Color {
        if entry.isOnAir { return Theme.Palette.textPrimary }
        return entry.hasEnded ? Theme.Palette.textTertiary : Theme.Palette.textPrimary
    }
}
