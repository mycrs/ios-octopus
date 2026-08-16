import Foundation
import OctopusCore
import OctopusDomain

/// Panelin yedek sunucu listesiyle çalışan adresi bulur.
///
/// ## Sıra
/// 1. Kayıtlı adres yanıt veriyorsa **hiçbir şey yapılmaz** — normal durumda
///    ek istek maliyeti yok.
/// 2. Yanıt vermiyorsa panelden yedek liste çekilir ve sırayla denenir.
/// 3. Hiçbiri yanıt vermezse kayıtlı adres döndürülür; hata mesajı
///    kullanıcının tanıdığı adresi göstersin.
///
/// Bulunan çalışan adres oturum boyunca hatırlanır: her istekte yeniden
/// tarama yapmak kanal değiştirmeyi yavaşlatırdı.
public actor DNSFailoverService: HostResolving {

    private let endpoint: PanelEndpoint
    private let httpClient: HTTPClient
    private let probeTimeout: TimeInterval

    private var cachedHosts: [URL]?
    /// Kayıtlı adres → bulunan çalışan adres.
    private var resolvedHosts: [String: URL] = [:]

    public init(
        endpoint: PanelEndpoint = PanelEndpoint(),
        httpClient: HTTPClient? = nil,
        probeTimeout: TimeInterval = 4
    ) {
        self.endpoint = endpoint
        // Yoklama hızlı olmalı: kullanıcı yayın açılmasını bekliyor.
        self.httpClient = httpClient ?? URLSessionHTTPClient(retryPolicy: .single)
        self.probeTimeout = probeTimeout
    }

    public func resolve(preferring current: URL) async -> URL {
        if let known = resolvedHosts[current.absoluteString] {
            return known
        }

        if await isReachable(current) {
            return current
        }

        Log.network.info("Kayıtlı sunucu yanıt vermiyor, yedekler deneniyor")

        for candidate in await hosts() where candidate != current {
            if await isReachable(candidate) {
                Log.network.info("Yedek sunucuya geçildi")
                resolvedHosts[current.absoluteString] = candidate
                return candidate
            }
        }

        // Hiçbiri çalışmıyor: kullanıcı kendi girdiği adresi görsün.
        return current
    }

    /// Kaynak düzenlendiğinde veya ağ değiştiğinde yeniden tarama yapılsın.
    public func reset() {
        resolvedHosts.removeAll()
        cachedHosts = nil
    }

    // MARK: - Yardımcılar

    private func hosts() async -> [URL] {
        if let cachedHosts { return cachedHosts }

        do {
            let data = try await httpClient.get(endpoint.dnsList, headers: [:])
            let list = try Self.parse(data)
            cachedHosts = list
            return list
        } catch {
            // ⚠️ Başarısızlık **önbelleğe alınmaz**. Buraya yalnızca kayıtlı
            // sunucu ölüyken geliniyor — yani ağın zaten sorunlu olduğu an.
            // Boş listeyi saklamak, o tek talihsiz isteğin failover'ı oturum
            // boyunca sessizce kapatması demekti: sonraki her çağrı önbellekten
            // `[]` alır, panele bir daha hiç sorulmazdı.
            Log.network.info("Yedek sunucu listesi alınamadı")
            return []
        }
    }

    private func isReachable(_ url: URL) async -> Bool {
        // Yoklama, panelin değil **yayın sunucusunun** ayakta olduğunu ölçer.
        do {
            _ = try await withTimeout(probeTimeout) {
                try await self.httpClient.get(url, headers: [:])
            }
            return true
        } catch let error as AppError {
            // 401/404 sunucunun AYAKTA olduğunu gösterir: yalnızca istek
            // reddedilmiştir. Ölü sunucu ağ hatası verir.
            switch error {
            case .unauthorized, .notFound, .invalidResponse:
                return true
            default:
                return false
            }
        } catch {
            return false
        }
    }

    private func withTimeout<T: Sendable>(
        _ seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AppError.network(reason: "Yoklama zaman aşımı")
            }
            guard let result = try await group.next() else {
                throw AppError.network(reason: "Yoklama sonuçsuz")
            }
            group.cancelAll()
            return result
        }
    }

    /// Panel listesi hem dizi hem `{servers:[…]}` biçiminde gelebiliyor.
    static func parse(_ data: Data) throws -> [URL] {
        let decoder = JSONDecoder()

        if let entries = try? decoder.decode([DNSEntryDTO].self, from: data) {
            return entries.compactMap { $0.url }
        }
        if let envelope = try? decoder.decode(DNSEnvelope.self, from: data) {
            return (envelope.servers ?? envelope.data ?? []).compactMap { $0.url }
        }
        throw AppError.invalidResponse(reason: "Sunucu listesi okunamadı")
    }
}

private struct DNSEnvelope: Decodable {
    let servers: [DNSEntryDTO]?
    let data: [DNSEntryDTO]?
}

struct DNSEntryDTO: Decodable {
    @Lenient var urlText: String?
    @Lenient var baseUrl: String?
    @Lenient var name: String?

    enum CodingKeys: String, CodingKey {
        case urlText = "url"
        case baseUrl = "base_url"
        case name
    }

    var url: URL? {
        guard var text = (urlText ?? baseUrl)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else { return nil }

        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        return URL(string: text)
    }
}
