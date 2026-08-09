import Foundation
import OctopusDomain

/// Oynatıcının anlık durumu.
public enum PlaybackState: Hashable, Sendable {
    case idle
    case loading
    case buffering
    case playing
    case paused
    case ended
    case failed(AppError)

    public var isActive: Bool {
        switch self {
        case .playing, .buffering: return true
        default: return false
        }
    }

    public var showsSpinner: Bool {
        switch self {
        case .loading, .buffering: return true
        default: return false
        }
    }
}

/// Zaman bilgisi. Canlı yayında `duration` yoktur.
public struct PlaybackTime: Hashable, Sendable {
    public let current: TimeInterval
    public let duration: TimeInterval?
    public let bufferedUpTo: TimeInterval

    public init(current: TimeInterval, duration: TimeInterval?, bufferedUpTo: TimeInterval) {
        self.current = current
        self.duration = duration
        self.bufferedUpTo = bufferedUpTo
    }

    public static let zero = PlaybackTime(current: 0, duration: nil, bufferedUpTo: 0)

    /// İlerleme çubuğu oranı. Canlıda anlamsızdır → 0.
    public var fraction: Double {
        guard let duration, duration > 0 else { return 0 }
        return min(max(current / duration, 0), 1)
    }
}

/// Görüntünün çerçeveye nasıl yerleşeceği.
///
/// ⚠️ IPTV'de gerçek bir ihtiyaç, süs değil: pek çok kanal 4:3 yayın
/// yapar ya da yayına kendi siyah bantlarını gömer. Sığdırma modunda
/// kullanıcı 16:9 ekranın ortasında küçücük bir görüntü izler.
public enum VideoFit: String, Hashable, Sendable, CaseIterable {
    /// En-boy oranı korunur; kenarlarda siyah bant kalabilir.
    case fit
    /// Çerçeve doldurulur; taşan kenarlar kırpılır.
    case fill

    public var toggled: VideoFit { self == .fit ? .fill : .fit }
}

/// Ses / altyazı / video izi.
public struct MediaTrack: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case audio
        case subtitle
        case video
    }

    public let id: String
    public let kind: Kind
    public let label: String
    public let languageCode: String?

    public init(id: String, kind: Kind, label: String, languageCode: String? = nil) {
        self.id = id
        self.kind = kind
        self.label = label
        self.languageCode = languageCode
    }
}

/// Motorun dışarı bildirdiği olaylar.
///
/// Motor `AsyncStream<PlaybackEvent>` yayınlar; `PlayerController` bunu
/// `@Published` özelliklere çevirir. Böylece motorlar SwiftUI bilmez.
public enum PlaybackEvent: Sendable {
    case stateChanged(PlaybackState)
    case timeChanged(PlaybackTime)
    case tracksDiscovered(audio: [MediaTrack], subtitle: [MediaTrack])
    case naturalSizeChanged(width: Double, height: Double)

    /// Motor bu içeriği açamadı — `PlayerController` yedek motora geçmeyi dener.
    case unrecoverableFailure(AppError)
}
