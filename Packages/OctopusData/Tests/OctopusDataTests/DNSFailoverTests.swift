import XCTest
import OctopusDomain
@testable import OctopusData

/// Ölü sunucuda yedeğe geçiş.
final class DNSFailoverTests: XCTestCase {

    private let primary = URL(string: "http://eski.example.com")!
    private let backup = URL(string: "http://yeni.example.com")!

    private func json(_ text: String) -> Data { Data(text.utf8) }

    /// - Parameter reachable: Yanıt veren adreslerin ana bilgisayar adları.
    private func makeService(
        reachable: Set<String>,
        listBody: String = #"[{"url":"http://yeni.example.com"}]"#,
        requestLog: LockedBox<[String]>? = nil
    ) -> DNSFailoverService {
        DNSFailoverService(
            httpClient: StubHTTPClient { url in
                requestLog?.set((requestLog?.get() ?? []) + [url.absoluteString])

                if url.path.contains("dns-list") {
                    return Data(listBody.utf8)
                }
                guard let host = url.host, reachable.contains(host) else {
                    throw AppError.network(reason: "erişilemiyor")
                }
                return Data()
            },
            probeTimeout: 1
        )
    }

    // MARK: - Normal durum

    func test_workingHostIsUsedWithoutFetchingList() async {
        // Kayıtlı adres çalışıyorsa ek istek maliyeti olmamalı.
        let log = LockedBox<[String]>([])
        let service = makeService(reachable: ["eski.example.com"], requestLog: log)

        let resolved = await service.resolve(preferring: primary)

        XCTAssertEqual(resolved, primary)
        XCTAssertFalse(
            log.get().contains { $0.contains("dns-list") },
            "Çalışan adres için yedek listesi çekilmemeli"
        )
    }

    // MARK: - Devreye girme

    func test_deadHostFallsBackToBackup() async {
        let service = makeService(reachable: ["yeni.example.com"])
        let resolved = await service.resolve(preferring: primary)
        XCTAssertEqual(resolved, backup)
    }

    func test_resolvedHostIsRemembered() async {
        // Her istekte yeniden tarama kanal değiştirmeyi yavaşlatırdı.
        let log = LockedBox<[String]>([])
        let service = makeService(reachable: ["yeni.example.com"], requestLog: log)

        _ = await service.resolve(preferring: primary)
        let countAfterFirst = log.get().count

        _ = await service.resolve(preferring: primary)
        XCTAssertEqual(log.get().count, countAfterFirst, "İkinci çağrı ağa çıkmamalı")
    }

    func test_resetForcesNewProbe() async {
        let log = LockedBox<[String]>([])
        let service = makeService(reachable: ["yeni.example.com"], requestLog: log)

        _ = await service.resolve(preferring: primary)
        let countAfterFirst = log.get().count

        await service.reset()
        _ = await service.resolve(preferring: primary)

        XCTAssertGreaterThan(log.get().count, countAfterFirst)
    }

    // MARK: - Başarısızlık

    func test_whenNothingWorksOriginalHostIsReturned() async {
        // Hata mesajı kullanıcının tanıdığı adresi göstermeli.
        let service = makeService(reachable: [])
        let resolved = await service.resolve(preferring: primary)
        XCTAssertEqual(resolved, primary)
    }

    func test_missingListDoesNotCrash() async {
        let service = DNSFailoverService(
            httpClient: StubHTTPClient { _ in throw AppError.network(reason: "kopuk") },
            probeTimeout: 1
        )
        let resolved = await service.resolve(preferring: primary)
        XCTAssertEqual(resolved, primary)
    }

    func test_listFetchFailureIsNotCachedForever() async {
        // ⚠️ Yedek listesi yalnızca kayıtlı sunucu ÖLÜYKEN çekilir — yani ağın
        // zaten sorunlu olduğu an. Başarısızlık önbelleğe alınırsa o tek
        // talihsiz istek failover'ı oturum boyunca sessizce kapatır: sonraki
        // her çağrı önbellekten boş liste alır, panele bir daha sorulmaz.
        let panelIsDown = LockedBox<Bool>(true)

        let service = DNSFailoverService(
            httpClient: StubHTTPClient { url in
                if url.path.contains("dns-list") {
                    if panelIsDown.get() { throw AppError.network(reason: "panel kopuk") }
                    return Data(#"[{"url":"http://yeni.example.com"}]"#.utf8)
                }
                guard url.host == "yeni.example.com" else {
                    throw AppError.network(reason: "erişilemiyor")
                }
                return Data()
            },
            probeTimeout: 1
        )

        // 1. tur: panel de ölü — kullanıcı kendi adresini görsün.
        let first = await service.resolve(preferring: primary)
        XCTAssertEqual(first, primary)

        // 2. tur: panel ayağa kalktı. Liste yeniden sorulmalı ve yedeğe geçilmeli.
        panelIsDown.set(false)
        let second = await service.resolve(preferring: primary)
        XCTAssertEqual(
            second,
            backup,
            "Başarısız liste isteği önbelleğe alınmamalı; panel dönünce yedek bulunmalı"
        )
    }

    // MARK: - Erişilebilirlik ölçütü

    func test_authErrorMeansHostIsAlive() async {
        // 401 sunucunun AYAKTA olduğunu gösterir; yalnızca istek reddedilmiştir.
        // Bunu "ölü" saymak çalışan sunucudan gereksiz yere kaçmak olurdu.
        let service = DNSFailoverService(
            httpClient: StubHTTPClient { url in
                if url.path.contains("dns-list") { return Data("[]".utf8) }
                throw AppError.unauthorized
            },
            probeTimeout: 1
        )

        let resolved = await service.resolve(preferring: primary)
        XCTAssertEqual(resolved, primary, "401 dönen sunucu ayakta sayılmalı")
    }

    // MARK: - Liste çözümleme

    func test_parsesPlainArray() throws {
        let hosts = try DNSFailoverService.parse(json("""
            [{"url":"http://a.example.com","name":"A"},
             {"base_url":"b.example.com"}]
            """))

        XCTAssertEqual(hosts.map(\.absoluteString), [
            "http://a.example.com",
            "http://b.example.com"   // şemasız adres tamamlanmalı
        ])
    }

    func test_parsesEnvelopeForms() throws {
        let servers = try DNSFailoverService.parse(json(#"{"servers":[{"url":"http://a.example.com"}]}"#))
        XCTAssertEqual(servers.count, 1)

        let data = try DNSFailoverService.parse(json(#"{"data":[{"url":"http://b.example.com"}]}"#))
        XCTAssertEqual(data.count, 1)
    }

    func test_entriesWithoutAddressAreSkipped() throws {
        let hosts = try DNSFailoverService.parse(json("""
            [{"name":"adressiz"},{"url":""},{"url":"http://gecerli.example.com"}]
            """))
        XCTAssertEqual(hosts.map(\.absoluteString), ["http://gecerli.example.com"])
    }

    func test_trailingSlashIsStripped() throws {
        let hosts = try DNSFailoverService.parse(json(#"[{"url":"http://a.example.com/"}]"#))
        XCTAssertEqual(hosts.first?.absoluteString, "http://a.example.com")
    }

    func test_malformedListThrows() {
        XCTAssertThrowsError(try DNSFailoverService.parse(json("<html>")))
    }
}
