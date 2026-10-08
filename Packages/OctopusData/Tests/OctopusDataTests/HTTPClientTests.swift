import XCTest
import OctopusDomain
@testable import OctopusData

/// Ağ katmanı: durum kodu çevirimi, yeniden deneme ve iptal davranışı.
final class HTTPClientTests: XCTestCase {

    private var session: URLSession!
    private var scenario: HTTPTestScenario!
    private var url: URL!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        // Önceki testin iptal edilen görevi gecikmeli başlayabilir. Her test
        // kendi adresi ve yanıt durumuyla çalışır; global sıra paylaşılmaz.
        url = URL(string: "http://panel.example.test/\(UUID().uuidString)/player_api.php")
        scenario = HTTPTestScenario()
        StubURLProtocol.register(scenario, for: url)
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        StubURLProtocol.unregister(url)
        session = nil
        scenario = nil
        super.tearDown()
    }

    private func makeClient(retry: RetryPolicy = .single) -> URLSessionHTTPClient {
        URLSessionHTTPClient(session: session, retryPolicy: retry)
    }

    // MARK: - Durum kodu çevirimi

    func test_successReturnsBody() async throws {
        scenario.respond(status: 200, body: Data("merhaba".utf8))
        let data = try await makeClient().get(url)
        XCTAssertEqual(String(data: data, encoding: .utf8), "merhaba")
    }

    func test_statusCodeMapping() {
        // Xtream panelleri süresi dolmuş abonelikte de 401/403 döner.
        XCTAssertThrowsError(try URLSessionHTTPClient.validate(statusCode: 401)) { error in
            XCTAssertEqual(error as? AppError, .unauthorized)
        }
        XCTAssertThrowsError(try URLSessionHTTPClient.validate(statusCode: 403)) { error in
            XCTAssertEqual(error as? AppError, .unauthorized)
        }
        XCTAssertThrowsError(try URLSessionHTTPClient.validate(statusCode: 404)) { error in
            XCTAssertEqual(error as? AppError, .notFound)
        }
        XCTAssertNoThrow(try URLSessionHTTPClient.validate(statusCode: 204))
    }

    // MARK: - Yeniden deneme

    func test_serverError_isRetriedUpToLimit() async throws {
        scenario.respond(status: 503, body: Data())
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.01, multiplier: 2)

        do {
            _ = try await makeClient(retry: policy).get(url)
            XCTFail("503 sonunda hata vermeliydi")
        } catch {
            XCTAssertEqual(scenario.requestCount, 3, "Üç deneme yapılmalıydı")
        }
    }

    func test_unauthorized_isNotRetried() async throws {
        // Yanlış parolayı üç kez denemenin anlamı yok — üstelik bazı paneller
        // tekrarlanan başarısız girişte hesabı geçici olarak kilitler.
        scenario.respond(status: 401, body: Data())
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.01, multiplier: 2)

        do {
            _ = try await makeClient(retry: policy).get(url)
            XCTFail("401 hata vermeliydi")
        } catch {
            XCTAssertEqual(error as? AppError, .unauthorized)
            XCTAssertEqual(scenario.requestCount, 1, "401 yeniden denenmemeli")
        }
    }

    func test_retrySucceedsAfterTransientFailure() async throws {
        // İlk istek 500, ikincisi başarılı.
        scenario.respondSequence([
            (503, Data()),
            (200, Data("tamam".utf8))
        ])
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.01, multiplier: 2)

        let data = try await makeClient(retry: policy).get(url)
        XCTAssertEqual(String(data: data, encoding: .utf8), "tamam")
        XCTAssertEqual(scenario.requestCount, 2)
    }

    func test_retryDelayGrowsExponentially() {
        let policy = RetryPolicy(maxAttempts: 4, baseDelay: 1.5, multiplier: 2)
        XCTAssertEqual(policy.delay(forAttempt: 1), 1.5)
        XCTAssertEqual(policy.delay(forAttempt: 2), 3.0)
        XCTAssertEqual(policy.delay(forAttempt: 3), 6.0)
    }

    // MARK: - Başlıklar

    func test_userAgentIsSent() async throws {
        // Birçok panel beklenmeyen User-Agent'a 403 döner.
        scenario.respond(status: 200, body: Data())
        _ = try await makeClient().get(url)

        let sent = scenario.lastRequest?.value(forHTTPHeaderField: "User-Agent")
        XCTAssertEqual(sent, URLSessionHTTPClient.defaultUserAgent)
    }

    func test_callerHeadersOverrideDefaults() async throws {
        scenario.respond(status: 200, body: Data())
        _ = try await makeClient().get(url, headers: ["User-Agent": "Özel/1.0"])

        let sent = scenario.lastRequest?.value(forHTTPHeaderField: "User-Agent")
        XCTAssertEqual(sent, "Özel/1.0")
    }

    // MARK: - İptal

    func test_cancellation_isNotSwallowedAsNetworkError() async throws {
        // Referans dersi: iptal genel hata yakalamaya düşerse yeniden denenir
        // ve iptal edilen iş ısrarla sürdürülür.
        scenario.respond(status: 200, body: Data(), delay: 2)

        let task = Task { try await makeClient(retry: .default).get(url) }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("İptal edilen istek sonuç döndürmemeli")
        } catch {
            XCTAssertTrue(
                error is CancellationError || (error as? URLError)?.code == .cancelled,
                "İptal, ağ hatası gibi ele alınmamalı: \(error)"
            )
        }
    }
}

// MARK: - Sahte ağ katmanı

private struct StubHTTPResponse {
    let status: Int
    let body: Data
    let delay: TimeInterval
}

/// Yanıt kuyruğu ve sayaç bir test oturumuna aittir.
private final class HTTPTestScenario: @unchecked Sendable {
    private var queue: [StubHTTPResponse] = []
    private var fallback: StubHTTPResponse?
    private var count = 0
    private var request: URLRequest?
    private let lock = NSLock()

    var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    var lastRequest: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return request
    }

    func respond(status: Int, body: Data, delay: TimeInterval = 0) {
        lock.lock(); defer { lock.unlock() }
        fallback = StubHTTPResponse(status: status, body: body, delay: delay)
    }

    func respondSequence(_ responses: [(Int, Data)]) {
        lock.lock(); defer { lock.unlock() }
        queue = responses.map { StubHTTPResponse(status: $0.0, body: $0.1, delay: 0) }
    }

    func next(for request: URLRequest) -> StubHTTPResponse {
        lock.lock(); defer { lock.unlock() }
        count += 1
        self.request = request
        if !queue.isEmpty { return queue.removeFirst() }
        return fallback ?? StubHTTPResponse(status: 200, body: Data(), delay: 0)
    }
}

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var scenarios: [URL: HTTPTestScenario] = [:]
    private static let registryLock = NSLock()
    private let deliveryLock = NSLock()
    private var stopped = false
    private var delivery: DispatchWorkItem?

    static func register(_ scenario: HTTPTestScenario, for url: URL) {
        registryLock.lock(); defer { registryLock.unlock() }
        scenarios[url] = scenario
    }

    static func unregister(_ url: URL) {
        registryLock.lock(); defer { registryLock.unlock() }
        scenarios[url] = nil
    }

    private static func scenario(for url: URL?) -> HTTPTestScenario? {
        registryLock.lock(); defer { registryLock.unlock() }
        return url.flatMap { scenarios[$0] }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        // Kapanmış testin geç kalan isteği gerçek ağa kaçamaz.
        request.url?.host == "panel.example.test"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let scenario = Self.scenario(for: request.url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        let response = scenario.next(for: request)

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.deliveryLock.lock()
            let stopped = self.stopped
            self.deliveryLock.unlock()
            guard !stopped else { return }
            let httpResponse = HTTPURLResponse(
                url: self.request.url ?? URL(string: "http://localhost")!,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            self.client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: response.body)
            self.client?.urlProtocolDidFinishLoading(self)
        }

        deliveryLock.lock()
        guard !stopped else { deliveryLock.unlock(); return }
        delivery = work
        deliveryLock.unlock()

        if response.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + response.delay, execute: work)
        } else {
            work.perform()
        }
    }

    override func stopLoading() {
        deliveryLock.lock(); defer { deliveryLock.unlock() }
        stopped = true
        delivery?.cancel()
        delivery = nil
    }
}
