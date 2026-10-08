import Foundation
import Combine
import UIKit
import OctopusDomain
import OctopusPlayback

@MainActor
final class SourceHealthViewModel: ObservableObject {
    @Published private(set) var snapshot: SourceHealthSnapshot?
    @Published private(set) var playback: PlaybackDiagnosticSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var shareText: String?

    private let dependencies: SettingsDependencies
    private let now: () -> Date
    private var generation = 0

    init(dependencies: SettingsDependencies, now: @escaping () -> Date = Date.init) {
        self.dependencies = dependencies
        self.now = now
    }

    func load() async {
        generation &+= 1
        let request = generation
        isLoading = true
        error = nil
        shareText = nil
        defer { if generation == request { isLoading = false } }
        do {
            guard let reader = dependencies.sourceHealth,
                  let playlist = try await dependencies.playlists.activePlaylist()
            else {
                if !Task.isCancelled, generation == request {
                    snapshot = nil
                    playback = nil
                }
                return
            }
            try Task.checkCancellation()
            let summary = try await reader.snapshot(playlistID: playlist.id, at: now())
            guard !Task.isCancelled, generation == request else { return }
            let player = dependencies.playerDiagnostics?()
            snapshot = summary
            playback = player
            shareText = try SourceSupportReport(
                catalog: summary, playback: player,
                appVersion: Self.appVersion, systemVersion: UIDevice.current.systemVersion
            ).text()
        } catch is CancellationError {
            // Ekran kapanınca iptal kullanıcı hatası değildir.
        } catch {
            guard !Task.isCancelled, generation == request else { return }
            snapshot = nil
            playback = nil
            self.error = "Kaynak kontrolü tamamlanamadı. Yeniden dene."
        }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "unknown"
        let build = (info?["CFBundleVersion"] as? String) ?? "unknown"
        return "\(version) (\(build))"
    }
}

/// Alanlar izin listesiyle belirlenir; Playlist veya ham log encode edilmez.
struct SourceSupportReport: Encodable {
    let schemaVersion = 1
    let catalog: SourceHealthSnapshot
    let playback: PlaybackDiagnosticSnapshot?
    let appVersion: String
    let systemVersion: String

    func text() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        guard let text = String(data: data, encoding: .utf8) else {
            throw AppError.invalidResponse(reason: "Destek raporu oluşturulamadı")
        }
        return text
    }
}
