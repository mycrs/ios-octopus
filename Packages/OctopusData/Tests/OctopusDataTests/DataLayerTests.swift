import XCTest
import OctopusDomain
@testable import OctopusData

/// Faz 2'de Xtream/M3U parser testleri buraya gelecek.
/// Şimdilik katmanın derlendiğini ve sözleşmelerin göründüğünü doğrular.
final class DataLayerTests: XCTestCase {

    func test_contentProviderProtocol_isVisibleToDataLayer() {
        // Derleme zamanı kontrolü: protokol var ve Domain tiplerini görüyor.
        let kinds = MediaCategory.Kind.allCases
        XCTAssertEqual(kinds.count, 3)
    }
}
