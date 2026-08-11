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
                                Text(channel.name)
                                    .foregroundStyle(Theme.Palette.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                if channel.id == currentSource {
                                    Image(systemName: "waveform")
                                        .foregroundStyle(Theme.Palette.accent)
                                }
                            }
                        }
                        .accessibilityAddTraits(
                            channel.id == currentSource ? [.isSelected] : []
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Canlı TV")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Kanal ara")
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
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(isCurrent ? Theme.Palette.accent : Theme.Palette.textSecondary)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(program.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(timeRange(program))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private func channelLogo(_ channel: Channel) -> some View {
        ChannelLogoView(url: channel.logoURL, size: 34)
    }

    private func timeRange(_ program: EPGProgram) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: program.startDate)) – "
            + formatter.string(from: program.endDate)
    }
}
