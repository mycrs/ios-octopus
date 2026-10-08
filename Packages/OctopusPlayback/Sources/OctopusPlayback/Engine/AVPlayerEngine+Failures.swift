import Foundation
import AVFoundation
import OctopusDomain

extension AVPlayerEngine {
    struct ClassifiedFailure {
        let error: AppError
        let kind: PlaybackFailureKind
    }

    nonisolated static func headerFailure(for headers: [String: String]) -> ClassifiedFailure? {
        let keys = Set(headers.keys.map { $0.lowercased() })
        guard !keys.subtracting(["user-agent"]).isEmpty else { return nil }
        let fallbackCanCarryHeaders = keys.subtracting(["user-agent", "referer"]).isEmpty
        return ClassifiedFailure(
            error: .playbackFailed(reason: "Bu yayının gerekli istek başlıkları sistem oynatıcısı tarafından desteklenmiyor."),
            kind: fallbackCanCarryHeaders ? .requiresFallbackHeaders : .unsupportedHeaders
        )
    }

    nonisolated static func classifiedFailure(
        statusCode: Int,
        error: NSError?
    ) -> ClassifiedFailure {
        switch statusCode {
        case 401:
            return ClassifiedFailure(error: .unauthorized, kind: .authorization)
        case 403:
            return ClassifiedFailure(
                error: .playbackFailed(reason: "Sunucu erişimi reddetti (403). Aboneliğin süresi dolmuş ya da aynı anda izin verilen cihaz sayısı aşılmış olabilir."),
                kind: .authorization
            )
        case 404, 410:
            return ClassifiedFailure(error: .notFound, kind: .missingResource)
        case 429, 500...599:
            return ClassifiedFailure(
                error: .network(reason: "Yayın sunucusu geçici olarak yanıt veremiyor."),
                kind: .network
            )
        default:
            break
        }

        // AVFoundation often wraps URLSession's error. Inspect a bounded cause chain;
        // never parse server messages or copy them into support reports.
        var cause = error
        for _ in 0..<8 {
            guard let current = cause else { break }
            if current.domain == NSURLErrorDomain {
                if current.code == URLError.userAuthenticationRequired.rawValue {
                    return ClassifiedFailure(error: .unauthorized, kind: .authorization)
                }
                if current.code == URLError.fileDoesNotExist.rawValue {
                    return ClassifiedFailure(error: .notFound, kind: .missingResource)
                }
                return ClassifiedFailure(
                    error: .network(reason: "Yayın bağlantısı kesildi. Bağlantını kontrol edip tekrar dene."),
                    kind: .network
                )
            }
            if current.domain == AVFoundationErrorDomain {
                switch current.code {
                case AVError.Code.decoderNotFound.rawValue, AVError.Code.decodeFailed.rawValue:
                    return ClassifiedFailure(
                        error: .playbackFailed(reason: "Görüntü çözülemedi. Yedek oynatıcı deneniyor."),
                        kind: .decoder
                    )
                case AVError.Code.fileFormatNotRecognized.rawValue, AVError.Code.failedToParse.rawValue:
                    return ClassifiedFailure(
                        error: .playbackFailed(reason: "Yayın biçimi sistem oynatıcısı tarafından desteklenmiyor."),
                        kind: .unsupportedFormat
                    )
                default:
                    break
                }
            }
            cause = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return ClassifiedFailure(
            error: .playbackFailed(reason: "Yayın açılamadı. Kaynağı kontrol edip tekrar dene."),
            kind: .unknown
        )
    }
}
