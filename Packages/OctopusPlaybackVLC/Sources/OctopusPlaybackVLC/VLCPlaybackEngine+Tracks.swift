import Foundation
import VLCKitSPM
import OctopusCore
import OctopusDomain
import OctopusPlayback

/// Ses ve altyazı izleri + VLC bildirimlerinin karşılanması.
///
/// VLC'de izler iki paralel dizidir: adlar ve indeksler. Seçim `Int32`
/// indeksle yapılır. Bu dosya ikisini `MediaTrack`'e çevirir, böylece UI
/// VLCKit bilmez — `AVPlayerEngine+Tracks` ile aynı sözleşme.
extension VLCPlaybackEngine {

    /// Altyazıyı kapatma seçeneğinin kimliği.
    ///
    /// ⚠️ `AVPlayerEngine` ile **aynı** dize olmalı: iz seçici ekranı
    /// motoru bilmez ve "Kapalı" satırını bu kimlikten tanır.
    static var subtitleOffTrackID: String { "subtitle.off" }

    /// VLC'de altyazı kapatma indeksi.
    static var subtitleOffIndex: Int32 { -1 }

    /// İzler yalnızca medya çözümlendikten sonra görünür; durum her
    /// değiştiğinde sorulur ve bir kez yayınlanır.
    ///
    /// ⚠️ Tek seferlik değil de "boşsa tekrar dene" mantığı: MPEG-TS'te
    /// izler yayının ortasında da belirebilir (yeni bir ses izi eklenmesi
    /// canlı yayında olağan).
    func refreshTracksIfNeeded() {
        let audioNames = player.audioTrackNames.compactMap { $0 as? String }
        let audioIndexes = player.audioTrackIndexes.compactMap { $0 as? NSNumber }
        let subtitleNames = player.videoSubTitlesNames.compactMap { $0 as? String }
        let subtitleIndexes = player.videoSubTitlesIndexes.compactMap { $0 as? NSNumber }

        let audioCount = min(audioNames.count, audioIndexes.count)
        let subtitleCount = min(subtitleNames.count, subtitleIndexes.count)
        guard audioCount + subtitleCount > 0 else { return }

        var indexes: [String: Int32] = [:]

        let audio = Self.tracks(
            names: audioNames,
            indexes: audioIndexes,
            kind: .audio,
            into: &indexes
        )
        let subtitle = Self.tracks(
            names: subtitleNames,
            indexes: subtitleIndexes,
            kind: .subtitle,
            into: &indexes
        )

        // Değişiklik yoksa yayınlama: her durum değişiminde aynı listeyi
        // basmak iz seçici ekranını gereksizce yeniden çizer.
        guard audio != audioTracks || subtitle != subtitleTracks else {
            syncSelectedTracks()
            return
        }

        trackIndexes = indexes
        publish(audio: audio, subtitle: subtitle)
        syncSelectedTracks()
    }

    /// Ad + indeks çiftlerini `MediaTrack` listesine çevirir.
    ///
    /// ⚠️ Kimlik **indeksten** üretiliyor, sıra numarasından değil: VLC
    /// listeye "Disable"ı (-1) da koyar ve sıra numarası kullanılsaydı
    /// kapatma satırı normal bir iz gibi seçilmeye çalışılırdı.
    private static func tracks(
        names: [String],
        indexes: [NSNumber],
        kind: MediaTrack.Kind,
        into map: inout [String: Int32]
    ) -> [MediaTrack] {
        zip(names, indexes).enumerated().compactMap { position, pair in
            let (name, number) = pair
            let index = number.int32Value

            // "Kapalı" satırı yalnızca altyazıda anlamlı. Seste VLC'nin
            // "Disable"ı sesi tamamen susturur — kullanıcıya sunulmamalı.
            if index == subtitleOffIndex {
                guard kind == .subtitle else { return nil }
                map[subtitleOffTrackID] = index
                return MediaTrack(id: subtitleOffTrackID, kind: .subtitle, label: "Kapalı")
            }

            let id = "\(kind.rawValue).\(index)"
            map[id] = index

            return MediaTrack(
                id: id,
                kind: kind,
                label: label(from: name, kind: kind, position: position),
                // VLC iz adında dili düz metin verir ("Turkish"), ISO kodu
                // sunmaz. Uydurmak yerine boş bırakılıyor.
                languageCode: nil
            )
        }
    }

    private static func label(from name: String, kind: MediaTrack.Kind, position: Int) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return kind == .audio ? "Ses \(position + 1)" : "Altyazı \(position + 1)"
    }

    /// Kullanıcının seçtiği izi uygular.
    public func select(track: MediaTrack) {
        guard let index = trackIndexes[track.id] else { return }

        switch track.kind {
        case .audio:
            player.currentAudioTrackIndex = index
        case .subtitle:
            player.currentVideoSubTitleIndex = index
        case .video:
            return
        }

        syncSelectedTracks()
    }

    /// VLC'nin **gerçek** seçimini okuyup yayınlar.
    ///
    /// ⚠️ Seçim yalnızca bizim çağrımızla değişmez: VLC açılışta kendi
    /// varsayılanını seçer. Menüde işaretli satır bu yüzden her defasında
    /// motora sorulur (bkz. `PlaybackEngine.selectedAudioTrack`).
    func syncSelectedTracks() {
        selectedAudioTrack = audioTracks.first {
            trackIndexes[$0.id] == player.currentAudioTrackIndex
        }

        // Altyazı listesi hiç yoksa "Kapalı" göstermek yanıltıcı olur.
        selectedSubtitleTrack = subtitleTracks.isEmpty
            ? nil
            : subtitleTracks.first { trackIndexes[$0.id] == player.currentVideoSubTitleIndex }
    }
}

/// VLC bildirimleri → motor durumu.
///
/// ⚠️ Delege çağrıları VLC'nin kendi iş parçacığından da gelebilir; motor
/// `@MainActor` izole olduğu için gövdeler ana aktöre atlar. UIKit
/// katmanına başka bir iş parçacığından dokunmak çökme sebebidir.
extension VLCPlaybackEngine: VLCMediaPlayerDelegate {

    public nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in syncState() }
    }

    public nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor in reportTime() }
    }
}
