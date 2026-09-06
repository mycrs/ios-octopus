import SwiftUI
import OctopusDesignSystem
import OctopusPlayback

/// Ses ve altyazı izi seçimi.
///
/// ⚠️ İşaretli satır **motordan** okunur, en son ne seçtiğimizden değil:
/// sistem açılışta cihaz diline göre kendi seçimini yapar. "Kullanıcı
/// henüz bir şey seçmedi" ile "sistem Türkçeyi seçti" farklı durumlar.
struct PlayerTrackPicker: View {

    /// Hangi izler gösterilecek.
    ///
    /// ⚠️ Ayrım kullanıcı isteğiydi: film ve dizide ses ile altyazı
    /// farklı ihtiyaçlar. Tek listede birleştirmek, altyazı arayan
    /// kullanıcıyı önce ses bölümünden geçmeye zorluyordu.
    enum Focus: String, Identifiable {
        case audio
        case subtitle

        var id: String { rawValue }

        var title: String {
            switch self {
            case .audio: return "Ses"
            case .subtitle: return "Altyazı"
            }
        }
    }

    let focus: Focus
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
                switch focus {
                case .audio:
                    section(tracks: audioTracks, selected: selectedAudio)
                case .subtitle:
                    section(tracks: subtitleTracks, selected: selectedSubtitle)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(LocalizedStringKey(focus.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Bitti") { dismiss() }
                }
            }
        }
    }

    private func section(
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
        }
    }
}
