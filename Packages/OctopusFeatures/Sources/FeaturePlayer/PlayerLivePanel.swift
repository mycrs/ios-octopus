import SwiftUI
import OctopusDomain
import OctopusDesignSystem

/// Yerel, ebeveyn filtresinden geçmiş kanal listesini video üstünde gösterir.
struct PlayerLivePanel: View {
    let channels: [Channel]
    let currentSource: Channel.ID?
    let currentProgram: EPGProgram?
    let followingProgram: EPGProgram?
    let onSelect: (Channel) -> Void
    let onDismiss: () -> Void

    @Environment(\.locale) private var locale
    @State private var searchText = ""
    @State private var showsAllChannels = false
    @FocusState private var isSearching: Bool

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            header
            searchBar
            channelList
            if let followingProgram { nextProgramSummary(followingProgram) }
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Palette.background.opacity(0.97), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), lineWidth: 0.5)
        }
        .tint(Theme.Palette.accent)
    }

    private var header: some View {
        HStack {
            Text("Kanallar")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(.white)
            Spacer(minLength: Theme.Spacing.xs)
            if currentCategoryID != nil {
                Menu {
                    Picker("Kanallar", selection: $showsAllChannels) {
                        Text("Geçerli kategori").tag(false)
                        Text("Tüm kanallar").tag(true)
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(showsAllChannels ? .white : Theme.Palette.accent)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Kanallar")
                .accessibilityValue(AppLocalization.localized(showsAllChannels ? "Tüm kanallar" : "Geçerli kategori", locale: locale))
                .accessibilityIdentifier("player.channels.scope")
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.localized("Kanal listesini kapat", locale: locale))
            .accessibilityIdentifier("player.channels.close")
        }
    }

    private var searchBar: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.6))
            TextField("Kanal ara", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearching)
                .onSubmit { isSearching = false }
                .foregroundStyle(.white)
                .accessibilityIdentifier("player.channels.search")
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.localized("Aramayı temizle", locale: locale))
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .frame(minHeight: 44)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    private var channelList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    if filteredChannels.isEmpty {
                        Text("Kanal bulunamadı")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(Theme.Spacing.md)
                    }
                    ForEach(filteredChannels) { channel in
                        channelRow(channel).id(channel.id)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { scrollToCurrent(proxy) }
            .onChange(of: currentSource) { _ in scrollToCurrent(proxy) }
            .onChange(of: filteredChannels.count) { _ in scrollToCurrent(proxy) }
        }
    }

    private func channelRow(_ channel: Channel) -> some View {
        let playing = channel.id == currentSource
        return Button { onSelect(channel) } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Text(displayNumber(for: channel))
                    .font(Theme.Typography.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.accent)
                    .frame(width: 32, alignment: .leading)
                ChannelLogoView(url: channel.logoURL, size: 34, fallbackText: channel.name)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .font(.subheadline.weight(playing ? .semibold : .regular))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if playing, let currentProgram {
                        Text(currentProgram.title).font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if playing {
                    Image(systemName: "waveform")
                        .foregroundStyle(Theme.Palette.accent)
                        .accessibilityLabel("Oynatılıyor")
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(playing ? Theme.Palette.accent.opacity(0.2) : Theme.Palette.surface.opacity(0.7),
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(playing ? [.isSelected] : [])
        .accessibilityIdentifier("player.channels.channel")
    }

    private var currentCategoryID: MediaCategory.ID? {
        channels.first { $0.id == currentSource }?.categoryID
    }

    private var filteredChannels: [Channel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let categoryID = currentCategoryID
        return channels.filter { channel in
            (showsAllChannels || categoryID == nil || channel.categoryID == categoryID)
                && (query.isEmpty || channel.name.localizedCaseInsensitiveContains(query)
                    || displayNumber(for: channel) == query)
        }
    }

    private func displayNumber(for channel: Channel) -> String {
        String(channel.number ?? channel.sortOrder + 1)
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let currentSource, filteredChannels.contains(where: { $0.id == currentSource }) else { return }
        proxy.scrollTo(currentSource, anchor: .center)
    }

    private func nextProgramSummary(_ program: EPGProgram) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(AppLocalization.localized("Sırada", locale: locale)) · \(program.startDate.formatted(.dateTime.hour().minute().locale(locale)))")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.accent)
            Text(program.title).font(.caption).foregroundStyle(.white).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
