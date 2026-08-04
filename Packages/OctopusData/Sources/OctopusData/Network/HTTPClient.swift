import Foundation
import OctopusCore
import OctopusDomain

/// Ağ erişimi sözleşmesi.
///
/// Protokol olması test için değil, **DNS failover** için de gerekli:
/// Faz 2'de bir sarmalayıcı, ölü sunucuda yedek adrese geçecek.
public protocol HTTPClient: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> Data
}

extension HTTPClient {
    public func get(_ url: URL) async throws -> Data {
        try await get(url, headers: [:])
    }
}

/// Yeniden deneme politikası.
///
/// Referans projede istekler zaman aşımsızdı ve yeniden deneme doğrusaldı;
/// kopuk bağlantıda uygulama sonsuza kadar takılıyordu. Burada hem üst sınır
/// hem de üstel geri çekilme var.
public struct RetryPolicy: Sendable, Equatable {

    public let maxAttempts: Int
    public let baseDelay: TimeInterval
    public let multiplier: Double

    public init(maxAttempts: Int, baseDelay: TimeInterval, multiplier: Double) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = baseDelay
        self.multiplier = multiplier
    }

    /// 3 deneme: 1,5 sn → 3 sn → vazgeç.
    public static let `default` = RetryPolicy(maxAttempts: 3, baseDelay: 1.5, multiplier: 2)

    /// Kullanıcı beklerken (giriş doğrulama) tek deneme yeterli.
    public static let single = RetryPolicy(maxAttempts: 1, baseDelay: 0, multiplier: 1)

    func shouldRetry(_ error: AppError, attempt: Int) -> Bool {
        guard attempt < maxAttempts else { return false }
        // Yeniden denenebilirlik bir İŞ KURALI ve Domain'de tanımlı:
        // yanlış parolayı üç kez denemenin anlamı yok.
        return error.isRetryable
    }

    func delay(forAttempt attempt: Int) -> TimeInterval {
        baseDelay * pow(multiplier, Double(attempt - 1))
    }
}

/// `URLSession` tabanlı varsayılan istemci.
public struct URLSessionHTTPClient: HTTPClient {

    private let session: URLSession
    private let retryPolicy: RetryPolicy
    private let defaultHeaders: [String: String]

    /// - Parameter userAgent: IPTV panellerinin çoğu `User-Agent` denetler ve
    ///   beklenmeyen değerde 403 döner. Varsayılan, yaygın kabul gören bir değer.
    public init(
        session: URLSession = .octopusDefault,
        retryPolicy: RetryPolicy = .default,
        userAgent: String = URLSessionHTTPClient.defaultUserAgent
    ) {
        self.session = session
        self.retryPolicy = retryPolicy
        self.defaultHeaders = ["User-Agent": userAgent]
    }

    public static let defaultUserAgent = "VLC/3.0.20 LibVLC/3.0.20"

    public func get(_ url: URL, headers: [String: String]) async throws -> Data {
        var attempt = 0

        while true {
            attempt += 1
            do {
                return try await perform(url: url, headers: headers)
            } catch is CancellationError {
                // İptal bir hata değil, kullanıcı/sistem kararıdır.
                // Yeniden denenirse iptal edilen iş ısrarla sürdürülür.
                throw CancellationError()
            } catch let error as AppError {
                guard retryPolicy.shouldRetry(error, attempt: attempt) else { throw error }
                Log.network.debug("İstek başarısız (deneme \(attempt)) — yeniden denenecek")
                try await Task.sleep(
                    nanoseconds: UInt64(retryPolicy.delay(forAttempt: attempt) * 1_000_000_000)
                )
            }
        }
    }

    private func perform(url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        for (key, value) in defaultHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        // Çağıranın başlıkları varsayılanları ezebilir.
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw AppError.wrap(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.invalidResponse(reason: "HTTP olmayan cevap")
        }

        try Self.validate(statusCode: httpResponse.statusCode)
        return data
    }

    /// HTTP durum kodunu uygulama diline çevirir.
    static func validate(statusCode: Int) throws {
        switch statusCode {
        case 200...299:
            return
        case 401, 403:
            // Xtream panelleri süresi dolmuş hesapta da 401/403 döner.
            throw AppError.unauthorized
        case 404:
            throw AppError.notFound
        case 429:
            throw AppError.network(reason: "Sunucu istek sınırı uyguluyor (429)")
        case 500...599:
            throw AppError.network(reason: "Sunucu hatası (\(statusCode))")
        default:
            throw AppError.invalidResponse(reason: "Beklenmeyen durum kodu: \(statusCode)")
        }
    }
}

extension URLSession {

    /// IPTV istekleri için yapılandırılmış oturum.
    public static let octopusDefault: URLSession = {
        let configuration = URLSessionConfiguration.default

        // Referans dersi: zaman aşımı olmayan istek, kopuk bağlantıda
        // uygulamayı süresiz kilitler.
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 120

        // Katalog ve EPG canlı veridir; sistem önbelleği bayat liste döndürebilir.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil

        // Bağlantı yokken kuyruğa alıp beklemek yerine hemen hata dön:
        // kullanıcı "çevrimdışı" bilgisini anında görmeli.
        configuration.waitsForConnectivity = false

        return URLSession(configuration: configuration)
    }()
}
