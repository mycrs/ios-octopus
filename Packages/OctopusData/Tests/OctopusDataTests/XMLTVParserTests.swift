import XCTest
import OctopusDomain
@testable import OctopusData

/// XMLTV çözümleyici: akış halinde teslim, zaman dilimleri, dayanıklılık.
final class XMLTVParserTests: XCTestCase {

    private func makeXML(_ programmes: String) -> Data {
        Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <tv>
            \(programmes)
            </tv>
            """.utf8)
    }

    private func parseAll(_ data: Data, chunkSize: Int = 2_000) throws -> [EPGProgram] {
        var collected: [EPGProgram] = []
        try XMLTVParser.parse(data: data, chunkSize: chunkSize) { chunk in
            collected.append(contentsOf: chunk)
        }
        return collected
    }

    // MARK: - Temel çözümleme

    func test_parsesProgrammeWithTitleAndDescription() throws {
        let programs = try parseAll(makeXML("""
            <programme start="20260804120000 +0300" stop="20260804130000 +0300" channel="trt1.tr">
              <title lang="tr">Haberler</title>
              <desc lang="tr">Günün haberleri</desc>
            </programme>
            """))

        XCTAssertEqual(programs.count, 1)
        XCTAssertEqual(programs[0].title, "Haberler")
        XCTAssertEqual(programs[0].summary, "Günün haberleri")
        XCTAssertEqual(programs[0].epgChannelID, "trt1.tr")
        XCTAssertEqual(programs[0].duration, 3_600)
    }

    func test_timeZoneOffsetIsApplied() throws {
        // +0300 ile 12:00 → UTC 09:00
        let programs = try parseAll(makeXML("""
            <programme start="20260804120000 +0300" stop="20260804130000 +0300" channel="c">
              <title>P</title>
            </programme>
            """))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(calendar.component(.hour, from: programs[0].startDate), 9)
    }

    func test_missingOffsetIsTreatedAsUTC() throws {
        let programs = try parseAll(makeXML("""
            <programme start="20260804120000" stop="20260804130000" channel="c">
              <title>P</title>
            </programme>
            """))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(calendar.component(.hour, from: programs[0].startDate), 12)
    }

    func test_firstTitleWinsInMultilingualGuides() throws {
        let programs = try parseAll(makeXML("""
            <programme start="20260804120000" stop="20260804130000" channel="c">
              <title lang="tr">Haberler</title>
              <title lang="en">News</title>
            </programme>
            """))
        XCTAssertEqual(programs[0].title, "Haberler")
    }

    func test_programWithoutTitleGetsPlaceholder() throws {
        let programs = try parseAll(makeXML("""
            <programme start="20260804120000" stop="20260804130000" channel="c"></programme>
            """))
        XCTAssertEqual(programs.count, 1)
        XCTAssertEqual(programs[0].title, "—", "Başlıksız program rehberde boşluk bırakmamalı")
    }

    // MARK: - Dayanıklılık

    func test_incompleteProgrammesAreSkippedButRestSurvive() throws {
        let programs = try parseAll(makeXML("""
            <programme stop="20260804130000" channel="c"><title>Başlangıç yok</title></programme>
            <programme start="20260804120000" channel="c"><title>Bitiş yok</title></programme>
            <programme start="20260804120000" stop="20260804130000"><title>Kanal yok</title></programme>
            <programme start="20260804120000" stop="20260804130000" channel="c"><title>Geçerli</title></programme>
            """))

        XCTAssertEqual(programs.map(\.title), ["Geçerli"])
    }

    func test_reversedTimeRangeIsRejected() throws {
        // Bitiş başlangıçtan önceyse rehber ızgarası bozulur.
        let programs = try parseAll(makeXML("""
            <programme start="20260804130000" stop="20260804120000" channel="c">
              <title>Ters</title>
            </programme>
            """))
        XCTAssertTrue(programs.isEmpty)
    }

    func test_malformedXMLThrows() {
        let broken = Data("<tv><programme><title>Kapanmamış".utf8)
        XCTAssertThrowsError(try parseAll(broken)) { error in
            guard case .invalidResponse = error as? AppError else {
                return XCTFail("Beklenen invalidResponse, gelen: \(error)")
            }
        }
    }

    func test_emptyGuideYieldsNoPrograms() throws {
        XCTAssertTrue(try parseAll(makeXML("")).isEmpty)
    }

    // MARK: - Akış halinde teslim
    //
    // 14.000 kanallı hesapta XMLTV yüzlerce megabayt olabilir; tek listede
    // toplamak uygulamayı düşürür.

    func test_programsAreDeliveredInChunks() throws {
        var programmes = ""
        for index in 0..<5 {
            programmes += """
                <programme start="2026080412\(String(format: "%02d", index))00" \
                stop="2026080413\(String(format: "%02d", index))00" channel="c\(index)">
                <title>P\(index)</title></programme>

                """
        }

        var chunkSizes: [Int] = []
        let total = try XMLTVParser.parse(data: makeXML(programmes), chunkSize: 2) { chunk in
            chunkSizes.append(chunk.count)
        }

        XCTAssertEqual(total, 5)
        XCTAssertEqual(chunkSizes, [2, 2, 1], "Programlar parçalar hâlinde teslim edilmeli")
    }

    func test_errorFromConsumerStopsParsing() throws {
        // Veritabanı yazımı başarısız olursa çözümleme sürdürülmemeli.
        struct WriteFailure: Error {}

        var programmes = ""
        for index in 0..<10 {
            programmes += """
                <programme start="2026080412\(String(format: "%02d", index))00" \
                stop="2026080413\(String(format: "%02d", index))00" channel="c">
                <title>P\(index)</title></programme>

                """
        }

        var deliveredChunks = 0
        XCTAssertThrowsError(
            try XMLTVParser.parse(data: makeXML(programmes), chunkSize: 2) { _ in
                deliveredChunks += 1
                throw WriteFailure()
            }
        ) { error in
            XCTAssertTrue(error is WriteFailure)
        }
        XCTAssertEqual(deliveredChunks, 1, "Hatadan sonra teslim sürmemeli")
    }

    // MARK: - İptal

    func test_cancelledTaskStopsParsing() async {
        var programmes = ""
        for index in 0..<200 {
            programmes += """
                <programme start="20260804120000" stop="20260804130000" channel="c\(index)">
                <title>P\(index)</title></programme>

                """
        }
        let data = makeXML(programmes)

        let task = Task<Int, Error> {
            try XMLTVParser.parse(data: data, chunkSize: 10) { _ in }
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("İptal edilen çözümleme tamamlanmamalı")
        } catch {
            XCTAssertTrue(error is CancellationError, "Beklenen CancellationError, gelen: \(error)")
        }
    }

    // MARK: - Kimlik

    func test_programIDsAreStableAcrossRuns() throws {
        let xml = makeXML("""
            <programme start="20260804120000" stop="20260804130000" channel="trt1.tr">
              <title>Haberler</title>
            </programme>
            """)

        // Aynı rehber iki kez çekildiğinde aynı kimlik üretilmeli;
        // aksi halde her senkronizasyon kopya kayıt yaratırdı.
        let first = try parseAll(xml)
        let second = try parseAll(xml)
        XCTAssertEqual(first[0].id, second[0].id)
    }
}
