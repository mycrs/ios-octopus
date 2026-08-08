import Foundation
import AVFoundation
import OctopusCore

/// Ses ve altyazı izleri.
///
/// AVFoundation'da izler `AVMediaSelectionGroup` üzerinden yönetilir;
/// "hangi seçenekler var" ve "hangisi seçili" ayrı sorulardır. Bu dosya
/// ikisini de `MediaTrack`'e çevirir, böylece UI AVFoundation bilmez.
extension AVPlayerEngine {

    /// Altyazıyı kapatma seçeneğinin kimliği.
    ///
    /// AVFoundation'da "altyazı yok" bir seçenek **değil**, seçimin
    /// `nil` olmasıdır. Listeye elle bir satır ekleniyor; aksi hâlde
    /// kullanıcı açtığı altyazıyı kapatamazdı.
    static let subtitleOffTrackID = "subtitle.off"

    static func makeSubtitleOffTrack() -> MediaTrack {
        MediaTrack(id: subtitleOffTrackID, kind: .subtitle, label: "Kapalı")
    }

    /// Asset'in medya seçim gruplarını okuyup izleri yayınlar.
    ///
    /// ⚠️ Ağ gecikmesine tabidir — bu yüzden `load()` bunu **beklemez**.
    /// İzler geldiğinde `tracksDiscovered` olayı düşer, UI o an tazelenir.
    func discoverTracks(in asset: AVAsset) async {
        do {
            let audioGroup = try await asset.loadMediaSelectionGroup(for: .audible)
            let subtitleGroup = try await asset.loadMediaSelectionGroup(for: .legible)

            guard !Task.isCancelled else { return }

            var options: [String: AVMediaSelectionOption] = [:]

            let audio = Self.tracks(from: audioGroup, kind: .audio, into: &options)
            var subtitle = Self.tracks(from: subtitleGroup, kind: .subtitle, into: &options)
            if !subtitle.isEmpty {
                subtitle.insert(Self.makeSubtitleOffTrack(), at: 0)
            }

            mediaGroups[.audio] = audioGroup
            mediaGroups[.subtitle] = subtitleGroup
            trackOptions = options

            publish(audio: audio, subtitle: subtitle)
            syncSelectedTracks()
        } catch {
            // İz okunamaması oynatmayı engellemez — çoğu canlı yayında
            // tek ses izi vardır ve seçim menüsü zaten gereksizdir.
            Log.playback.notice("İzler okunamadı: \(error.localizedDescription)")
        }
    }

    /// Bir seçim grubunu `MediaTrack` listesine çevirir.
    ///
    /// Grup yoksa (`nil`) boş liste döner — tek ses izli yayınlarda
    /// AVFoundation grup bile üretmez.
    private static func tracks(
        from group: AVMediaSelectionGroup?,
        kind: MediaTrack.Kind,
        into options: inout [String: AVMediaSelectionOption]
    ) -> [MediaTrack] {
        guard let group else { return [] }

        return group.options.enumerated().map { index, option in
            let id = "\(kind.rawValue).\(index)"
            options[id] = option

            return MediaTrack(
                id: id,
                kind: kind,
                // `displayName` sistem diline göre yerelleşir; boş gelirse
                // dil etiketine düşülür, o da yoksa sıra numarası.
                label: Self.label(for: option, kind: kind, index: index),
                languageCode: option.extendedLanguageTag
            )
        }
    }

    private static func label(
        for option: AVMediaSelectionOption,
        kind: MediaTrack.Kind,
        index: Int
    ) -> String {
        let name = option.displayName
        if !name.isEmpty { return name }
        if let tag = option.extendedLanguageTag, !tag.isEmpty { return tag }
        return kind == .audio ? "Ses \(index + 1)" : "Altyazı \(index + 1)"
    }

    /// Kullanıcının seçtiği izi uygular.
    public func select(track: MediaTrack) {
        guard let playerItem = player.currentItem else { return }

        if track.id == Self.subtitleOffTrackID {
            if let group = mediaGroups[.subtitle] {
                playerItem.select(nil, in: group)
            }
            syncSelectedTracks()
            return
        }

        guard
            let option = trackOptions[track.id],
            let group = mediaGroups[track.kind]
        else { return }

        playerItem.select(option, in: group)
        syncSelectedTracks()
    }

    /// AVFoundation'ın güncel seçimini okuyup yayınlar.
    ///
    /// Seçim yalnızca bizim `select` çağrımızla değişmez: sistem, cihaz
    /// diline ve erişilebilirlik ayarlarına göre açılışta kendisi bir iz
    /// seçer. Bu yüzden gerçek durum her seferinde AVFoundation'dan okunur.
    func syncSelectedTracks() {
        guard let playerItem = player.currentItem else { return }

        let selection = playerItem.currentMediaSelection

        selectedAudioTrack = mediaGroups[.audio]
            .flatMap { selection.selectedMediaOption(in: $0) }
            .flatMap { matchingTrack(for: $0, kind: .audio) }

        if let subtitleGroup = mediaGroups[.subtitle] {
            if let option = selection.selectedMediaOption(in: subtitleGroup) {
                selectedSubtitleTrack = matchingTrack(for: option, kind: .subtitle)
            } else {
                // Seçim yok = altyazı kapalı. Ama grup hiç yoksa altyazı
                // diye bir kavram da yok; "Kapalı" göstermek yanıltırdı.
                selectedSubtitleTrack = subtitleGroup.options.isEmpty
                    ? nil
                    : Self.makeSubtitleOffTrack()
            }
        } else {
            selectedSubtitleTrack = nil
        }
    }

    private func matchingTrack(
        for option: AVMediaSelectionOption,
        kind: MediaTrack.Kind
    ) -> MediaTrack? {
        guard let id = trackOptions.first(where: { $0.value == option })?.key else { return nil }
        let list = kind == .audio ? audioTracks : subtitleTracks
        return list.first { $0.id == id }
    }
}
