import Foundation
import AVFoundation
import OctopusCore

/// Bloklayan sistem ses çağrıları ana thread dışında ve sırayla yürür.
/// Aynı worker iki motor arasında paylaşılır: eski deactivation yeni
/// activation'dan sonra çalışıp güncel oynatmayı susturamaz.
public final class AudioSessionWorker: Sendable {
    private let queue = DispatchQueue(label: "com.octopus.iptv.audio-session", qos: .userInitiated)
    private let activateOperation: @Sendable () throws -> Void
    private let deactivateOperation: @Sendable () throws -> Void

    public init(session: AVAudioSession = .sharedInstance()) {
        let access = SessionAccess(session)
        activateOperation = {
            let session = access.session
            if session.category != .playback || session.mode != .moviePlayback || !session.categoryOptions.isEmpty {
                try session.setCategory(.playback, mode: .moviePlayback, options: [])
            }
            try session.setActive(true, options: [])
        }
        deactivateOperation = {
            try access.session.setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    init(activate: @escaping @Sendable () throws -> Void, deactivate: @escaping @Sendable () throws -> Void) {
        activateOperation = activate
        deactivateOperation = deactivate
    }

    // Kuyruğa ekleme motorların MainActor yaşam döngüsüyle aynı sırada olur.
    // Bloklayan sistem çağrısı yine yalnızca arka plan kuyruğunda çalışır.
    @MainActor
    public func activate() async {
        guard !Task.isCancelled else { return }
        await withCheckedContinuation { continuation in
            queue.async { [activateOperation] in
                do { try activateOperation() }
                catch { Log.playback.error("Ses oturumu açılamadı: \(error.localizedDescription)") }
                continuation.resume()
            }
        }
    }

    public func deactivate() {
        queue.async { [deactivateOperation] in
            do { try deactivateOperation() }
            catch { Log.playback.error("Ses oturumu kapatılamadı: \(error.localizedDescription)") }
        }
    }
}

/// AVAudioSession süreç genelinde thread-safe sistem nesnesidir.
/// Buradaki mutasyonların tamamı worker'ın seri kuyruğunda yapılır.
private final class SessionAccess: @unchecked Sendable {
    let session: AVAudioSession
    init(_ session: AVAudioSession) { self.session = session }
}
