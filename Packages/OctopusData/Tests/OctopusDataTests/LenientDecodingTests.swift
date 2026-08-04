import XCTest
@testable import OctopusData

/// Xtream panellerinin tip tutarsızlığına karşı dayanıklılık.
///
/// Buradaki her senaryo gerçek panellerde görülen bir gösterimdir.
/// Tek bir tutarsız alan yüzünden tüm kanal listesinin düşmesi kabul edilemez.
final class LenientDecodingTests: XCTestCase {

    private struct Sample: Decodable {
        @Lenient var streamID: Int?
        @Lenient var rating: Double?
        @Lenient var name: String?
        @Lenient var archive: Bool?
    }

    private func decode(_ json: String) throws -> Sample {
        try JSONDecoder().decode(Sample.self, from: Data(json.utf8))
    }

    // MARK: - Sayılar

    func test_intAcceptsNumberAndString() throws {
        XCTAssertEqual(try decode(#"{"streamID": 12345}"#).streamID, 12345)
        XCTAssertEqual(try decode(#"{"streamID": "12345"}"#).streamID, 12345)
        // Bazı paneller epoch'u ondalıklı dizgi olarak döndürüyor.
        XCTAssertEqual(try decode(#"{"streamID": "7.0"}"#).streamID, 7)
    }

    func test_doubleAcceptsEveryCommonForm() throws {
        XCTAssertEqual(try decode(#"{"rating": 7.5}"#).rating, 7.5)
        XCTAssertEqual(try decode(#"{"rating": "7.5"}"#).rating, 7.5)
        XCTAssertEqual(try decode(#"{"rating": 8}"#).rating, 8.0)
    }

    // MARK: - Dizgiler

    func test_emptyAndNullStringsBecomeNil() throws {
        // Panellerin boş alanı "" veya "null" döndürmesi çok yaygın —
        // bunlar ekranda "null" yazısı olarak görünmemeli.
        XCTAssertNil(try decode(#"{"name": ""}"#).name)
        XCTAssertNil(try decode(#"{"name": "   "}"#).name)
        XCTAssertNil(try decode(#"{"name": "null"}"#).name)
        XCTAssertEqual(try decode(#"{"name": "TRT 1"}"#).name, "TRT 1")
    }

    func test_stringAcceptsNumericValue() throws {
        XCTAssertEqual(try decode(#"{"name": 42}"#).name, "42")
    }

    // MARK: - Mantıksal değerler

    func test_boolAcceptsNumericAndTextualForms() throws {
        XCTAssertEqual(try decode(#"{"archive": 1}"#).archive, true)
        XCTAssertEqual(try decode(#"{"archive": 0}"#).archive, false)
        XCTAssertEqual(try decode(#"{"archive": "1"}"#).archive, true)
        XCTAssertEqual(try decode(#"{"archive": "true"}"#).archive, true)
        XCTAssertEqual(try decode(#"{"archive": false}"#).archive, false)
    }

    // MARK: - Dayanıklılık

    func test_missingKeysDoNotFailDecoding() throws {
        let sample = try decode("{}")
        XCTAssertNil(sample.streamID)
        XCTAssertNil(sample.rating)
        XCTAssertNil(sample.name)
        XCTAssertNil(sample.archive)
    }

    func test_unexpectedTypesYieldNilInsteadOfThrowing() throws {
        // ASIL KORUMA: bir alan beklenmedik tipte gelse bile kayıt ayakta kalır.
        // Katı kod çözme burada tüm listeyi düşürürdü.
        let sample = try decode(#"{"streamID": {"nested": 1}, "name": "TRT 1"}"#)
        XCTAssertNil(sample.streamID)
        XCTAssertEqual(sample.name, "TRT 1", "Diğer alanlar korunmalı")
    }

    func test_nullValuesAreTolerated() throws {
        let sample = try decode(#"{"streamID": null, "name": null}"#)
        XCTAssertNil(sample.streamID)
        XCTAssertNil(sample.name)
    }

    // MARK: - Tarih dönüşümü

    func test_epochConversion() {
        XCTAssertEqual(
            XtreamDate.fromEpoch(1_600_000_000),
            Date(timeIntervalSince1970: 1_600_000_000)
        )
        XCTAssertNil(XtreamDate.fromEpoch(0), "0 epoch 'tarih yok' demektir")
        XCTAssertNil(XtreamDate.fromEpoch(nil))
    }

    func test_dayStringConversion() {
        let date = XtreamDate.fromDayString("2020-05-17")
        XCTAssertNotNil(date)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(calendar.component(.year, from: date!), 2020)
        XCTAssertEqual(calendar.component(.month, from: date!), 5)
        XCTAssertEqual(calendar.component(.day, from: date!), 17)

        XCTAssertNil(XtreamDate.fromDayString(""))
        XCTAssertNil(XtreamDate.fromDayString("bozuk"))
    }
}
