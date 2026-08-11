import SwiftUI
import OctopusDomain
import OctopusDesignSystem

struct PlayerLivePanel: View {
    let channels: [Channel]
    let currentSource: Channel.ID?
    let currentProgram: EPGProgram?
    let followingProgram: EPGProgram?
    let onSelect: (Channel) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                if currentProgram != nil || followingProgram != nil {
                    guideSection
                }

                Section("Kanallar") {
                    ForEach(filteredChannels) { channel in
                        Button { onSelect(channel) } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                channelLogo(channel)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(channel.name)
                                        .font(Theme.Typography.rowTitle)
                                        .foregroundStyle(Theme.Palette.textPrimary)
                                        .lineLimit(1)
                                    if let number = channel.number {
                                        Text("#\(number)")
                                            .font(Theme.Typography.caption)
                                            .foregroundStyle(Theme.Palette.textSecondary)
                                    }
                                }
                                Spacer()
                                if channel.id == currentSource {
                                    Label("Oynatılıyor", systemImage: "waveform")
                                        .labelStyle(.iconOnly)
                                        .foregroundStyle(Theme.Palette.accent)
                                }
                            }
                            .padding(.vertical, Theme.Spacing.xxs)
                        }
                        .listRowBackground(
                            channel.id == currentSource
                                ? Theme.Palette.accent.opacity(0.10)
                                : Theme.Palette.surface
                        )
                        .accessibilityAddTraits(
                            channel.id == currentSource ? [.isSelected] : []
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.background)
            .navigationTitle("Canlı TV")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Kanal ara"
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Bitti") { dismiss() }
                }
            }
        }
    }

    private var filteredChannels: [Channel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return channels }
        return channels.filter { channel in
            channel.name.localizedCaseInsensitiveContains(query)
                || channel.number.map { String($0) } == query
        }
    }

    private var guideSection: some View {
        Section("Program") {
            if let currentProgram {
                programRow(label: "Şimdi", program: currentProgram, isCurrent: true)
            }
            if let followingProgram {
                programRow(label: "Sırada", program: followingProgram, isCurrent: false)
            }
        }
    }

    private func programRow(
        label: String,
        program: EPGProgram,
        isCurrent: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Text(AppLocalization.localized(label, locale: locale))
                .font(Theme.Typography.caption)
                .foregroundStyle(isCurrent ? Theme.Palette.accent : Theme.Palette.textSecondary)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(program.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(timeRange(program))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                if isCurrent {
                    ProgressView(value: program.progress(at: .now))
                        .progressViewStyle(.linear)
                        .tint(Theme.Palette.accent)
                }
            }
        }
    }

    private func channelLogo(_ channel: Channel) -> some View {
        ChannelLogoView(url: channel.logoURL, size: 38, fallbackText: channel.name)
    }

    private func timeRange(_ program: EPGProgram) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: program.startDate)) – "
            + formatter.string(from: program.endDate)
    }
}
