import XCTest
import OctopusDomain
@testable import OctopusData

/// Ağ katmanı: durum kodu çevirimi, yeniden deneme ve iptal davranışı.
final class HTTPClientTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func makeClient(retry: RetryPolicy = .single) -> URLSessionHTTPClient {
        URLSessionHTTPClient(session: session, retryPolicy: retry)
    }

    private let url = URL(string: "http://panel.example.com/player_api.php")!

    // MARK: - Durum kodu çevirimi

    func test_successReturnsBody() async throws {
        StubURLProtocol.respond(status: 200, body: Data("merhaba".utf8))
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
        StubURLProtocol.respond(status: 503, body: Data())
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.01, multiplier: 2)

        do {
            _ = try await makeClient(retry: policy).get(url)
            XCTFail("503 sonunda hata vermeliydi")
        } catch {
            XCTAssertEqual(StubURLProtocol.requestCount, 3, "Üç deneme yapılmalıydı")
        }
    }

    func test_unauthorized_isNotRetried() async throws {
        // Yanlış parolayı üç kez denemenin anlamı yok — üstelik bazı paneller
        // tekrarlanan başarısız girişte hesabı geçici olarak kilitler.
        StubURLProtocol.respond(status: 401, body: Data())
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.01, multiplier: 2)

        do {
            _ = try await makeClient(retry: policy).get(url)
            XCTFail("401 hata vermeliydi")
        } catch {
            XCTAssertEqual(error as? AppError, .unauthorized)
            XCTAssertEqual(StubURLProtocol.requestCount, 1, "401 yeniden denenmemeli")
        }
    }

    func test_retrySucceedsAfterTransientFailure() async throws {
        // İlk istek 500, ikincisi başarılı.
        StubURLProtocol.respondSequence([
            (503, Data()),
            (200, Data("tamam".utf8))
        ])
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.01, multiplier: 2)

        let data = try await makeClient(retry: policy).get(url)
        XCTAssertEqual(String(data: data, encoding: .utf8), "tamam")
        XCTAssertEqual(StubURLProtocol.requestCount, 2)
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
        StubURLProtocol.respond(status: 200, body: Data())
        _ = try await makeClient().get(url)

        let sent = StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "User-Agent")
        XCTAssertEqual(sent, URLSessionHTTPClient.defaultUserAgent)
    }

    func test_callerHeadersOverrideDefaults() async throws {
        StubURLProtocol.respond(status: 200, body: Data())
        _ = try await makeClient().get(url, headers: ["User-Agent": "Özel/1.0"])

        let sent = StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "User-Agent")
        XCTAssertEqual(sent, "Özel/1.0")
    }

    // MARK: - İptal

    func test_cancellation_isNotSwallowedAsNetworkError() async throws {
        // Referans dersi: iptal genel hata yakalamaya düşerse yeniden denenir
        // ve iptal edilen iş ısrarla sürdürülür.
        StubURLProtocol.respond(status: 200, body: Data(), delay: 2)

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

final class StubURLProtocol: URLProtocol {

    private struct Response {
        let status: Int
        let body: Data
        let delay: TimeInterval
    }

    nonisolated(unsafe) private static var queue: [Response] = []
    nonisolated(unsafe) private static var fallback: Response?
    nonisolated(unsafe) private(set) static var requestCount = 0
    nonisolated(unsafe) private(set) static var lastRequest: URLRequest?
    private static let lock = NSLock()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        queue = []
        fallback = nil
        requestCount = 0
        lastRequest = nil
    }

    static func respond(status: Int, body: Data, delay: TimeInterval = 0) {
        lock.lock(); defer { lock.unlock() }
        fallback = Response(status: status, body: body, delay: delay)
    }

    static func respondSequence(_ responses: [(Int, Data)]) {
        lock.lock(); defer { lock.unlock() }
        queue = responses.map { Response(status: $0.0, body: $0.1, delay: 0) }
    }

    private static func next() -> Response {
        lock.lock(); defer { lock.unlock() }
        requestCount += 1
        if !queue.isEmpty { return queue.removeFirst() }
        return fallback ?? Response(status: 200, body: Data(), delay: 0)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.lastRequest = request
        Self.lock.unlock()

        let response = Self.next()

        let deliver = { [weak self] in
            guard let self else { return }
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

        if response.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + response.delay, execute: deliver)
        } else {
            deliver()
        }
    }

    override func stopLoading() {}
}
