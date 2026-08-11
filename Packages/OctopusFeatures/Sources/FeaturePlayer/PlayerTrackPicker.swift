import SwiftUI
import OctopusDesignSystem
import OctopusPlayback

/// Ses ve altyazı izi seçimi.
///
/// ⚠️ İşaretli satır **motordan** okunur, en son ne seçtiğimizden değil:
/// sistem açılışta cihaz diline göre kendi seçimini yapar. "Kullanıcı
/// henüz bir şey seçmedi" ile "sistem Türkçeyi seçti" farklı durumlar.
struct PlayerTrackPicker: View {

    let audioTracks: [MediaTrack]
    let subtitleTracks: [MediaTrack]
    let selectedAudio: MediaTrack?
    let selectedSubtitle: MediaTrack?
    let onSelect: (MediaTrack) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            List {
                // Tek seçenekli grup gösterilmez: seçim yapılamayan bir
                // listeyi göstermek kullanıcıya iş çıkarır, seçenek sunmaz.
                if audioTracks.count > 1 {
                    section(
                        title: "Ses",
                        tracks: audioTracks,
                        selected: selectedAudio
                    )
                }

                if !subtitleTracks.isEmpty {
                    section(
                        title: "Altyazı",
                        tracks: subtitleTracks,
                        selected: selectedSubtitle
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Ses ve altyazı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Bitti") { dismiss() }
                }
            }
        }
    }

    private func section(
        title: String,
        tracks: [MediaTrack],
        selected: MediaTrack?
    ) -> some View {
        Section {
            ForEach(tracks) { track in
                Button {
                    onSelect(track)
                    dismiss()
                } label: {
                    HStack {
                        Text(AppLocalization.localized(track.label, locale: locale))
                            .foregroundColor(Theme.Palette.textPrimary)
                        Spacer()
                        if track.id == selected?.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(Theme.Palette.accent)
                        }
                    }
                }
                .accessibilityAddTraits(track.id == selected?.id ? [.isSelected] : [])
            }
        } header: {
            Text(LocalizedStringKey(title))
        }
    }
}
