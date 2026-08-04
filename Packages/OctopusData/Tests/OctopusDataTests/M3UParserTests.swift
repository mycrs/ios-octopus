import XCTest
import OctopusDomain
@testable import OctopusData

/// M3U çözümleyici. Örnekler gerçek listelerde karşılaşılan biçimlerdir.
final class M3UParserTests: XCTestCase {

    private func parse(_ text: String) -> M3UParser.Result {
        M3UParser.parse(text, playlistID: "p1")
    }

    // MARK: - Temel biçim

    func test_parsesStandardEntry() {
        let result = parse("""
            #EXTM3U
            #EXTINF:-1 tvg-id="trt1.tr" tvg-name="TRT 1" tvg-logo="http://logo.example.com/trt1.png" group-title="ULUSAL",TRT 1 HD
            http://sunucu.example.com/live/u/p/12345.ts
            """)

        XCTAssertEqual(result.channels.count, 1)
        let channel = result.channels[0]
        XCTAssertEqual(channel.name, "TRT 1 HD")
        XCTAssertEqual(channel.epgChannelID, "trt1.tr")
        XCTAssertEqual(channel.logoURL?.absoluteString, "http://logo.example.com/trt1.png")
        XCTAssertEqual(channel.streamKey, "http://sunucu.example.com/live/u/p/12345.ts")
        XCTAssertEqual(result.categories.map(\.name), ["ULUSAL"])
        XCTAssertEqual(channel.categoryID, result.categories[0].id)
    }

    func test_commaInsideAttributeDoesNotBreakName() {
        // ⚠️ Görünen ad tırnak DIŞINDAKİ son virgülden sonra başlar.
        // İlk virgüle bakan bir çözümleyici burada kırılırdı.
        let result = parse("""
            #EXTINF:-1 group-title="Spor, Yerel" tvg-name="A Spor",A Spor HD
            http://sunucu.example.com/1.ts
            """)

        XCTAssertEqual(result.channels[0].name, "A Spor HD")
        XCTAssertEqual(result.categories.map(\.name), ["Spor, Yerel"])
    }

    func test_nameFallsBackToTvgNameThenFileName() {
        let withTvgName = parse("""
            #EXTINF:-1 tvg-name="Yedek Ad"
            http://sunucu.example.com/1.ts
            """)
        XCTAssertEqual(withTvgName.channels[0].name, "Yedek Ad")

        let withNothing = parse("""
            #EXTINF:-1
            http://sunucu.example.com/kanal5.ts
            """)
        XCTAssertEqual(withNothing.channels[0].name, "kanal5.ts")
    }

    // MARK: - Alternatif biçimler

    func test_extgrpDirectiveProvidesCategory() {
        // Bazı listeler grubu ayrı satırda bildirir.
        let result = parse("""
            #EXTINF:-1,Kanal
            #EXTGRP:HABER
            http://sunucu.example.com/1.ts
            """)

        XCTAssertEqual(result.categories.map(\.name), ["HABER"])
    }

    func test_groupTitleWinsOverExtgrp() {
        let result = parse("""
            #EXTINF:-1 group-title="ÖNCELİKLİ",Kanal
            #EXTGRP:IKINCIL
            http://sunucu.example.com/1.ts
            """)
        XCTAssertEqual(result.categories.map(\.name), ["ÖNCELİKLİ"])
    }

    func test_channelNumberIsRead() {
        let result = parse("""
            #EXTINF:-1 tvg-chno="42",Kanal
            http://sunucu.example.com/1.ts
            """)
        XCTAssertEqual(result.channels[0].number, 42)
    }

    func test_ignoresUnknownDirectives() {
        let result = parse("""
            #EXTM3U x-tvg-url="http://epg.example.com/guide.xml"
            #EXTVLCOPT:network-caching=1000
            #EXTINF:-1,Kanal
            #EXTVLCOPT:http-user-agent=VLC
            http://sunucu.example.com/1.ts
            """)
        XCTAssertEqual(result.channels.count, 1)
        XCTAssertEqual(result.channels[0].name, "Kanal")
    }

    // MARK: - Dayanıklılık

    func test_malformedEntriesAreSkippedButListSurvives() {
        let result = parse("""
            #EXTM3U
            http://basliksiz.example.com/1.ts
            #EXTINF:-1,Geçerli
            http://sunucu.example.com/2.ts
            #EXTINF:-1,Adres bozuk
            bu-bir-adres-degil
            """)

        XCTAssertEqual(result.channels.map(\.name), ["Geçerli"], "Bozuk giriş listeyi düşürmemeli")
        XCTAssertEqual(result.skippedCount, 2)
    }

    func test_emptyInputYieldsEmptyResult() {
        let result = parse("")
        XCTAssertTrue(result.channels.isEmpty)
        XCTAssertTrue(result.categories.isEmpty)
    }

    func test_handlesWindowsLineEndingsAndBlankLines() {
        let result = parse("#EXTM3U\r\n\r\n#EXTINF:-1,Kanal\r\nhttp://sunucu.example.com/1.ts\r\n")
        XCTAssertEqual(result.channels.count, 1)
        XCTAssertEqual(result.channels[0].name, "Kanal")
    }

    // MARK: - Kategoriler

    func test_categoriesAreDeduplicatedAndOrderedByFirstAppearance() {
        let result = parse("""
            #EXTINF:-1 group-title="SPOR",A
            http://sunucu.example.com/1.ts
            #EXTINF:-1 group-title="HABER",B
            http://sunucu.example.com/2.ts
            #EXTINF:-1 group-title="SPOR",C
            http://sunucu.example.com/3.ts
            """)

        XCTAssertEqual(result.categories.map(\.name), ["SPOR", "HABER"])
        XCTAssertEqual(result.categories.map(\.sortOrder), [0, 1])
        // Aynı gruptaki kanallar aynı kategoriye bağlanmalı.
        XCTAssertEqual(result.channels[0].categoryID, result.channels[2].categoryID)
    }

    func test_channelsWithoutGroupHaveNoCategory() {
        let result = parse("""
            #EXTINF:-1,Kanal
            http://sunucu.example.com/1.ts
            """)
        XCTAssertNil(result.channels[0].categoryID)
        XCTAssertTrue(result.categories.isEmpty)
    }

    // MARK: - Kimlik

    func test_identifiersAreScopedToPlaylist() {
        let text = """
            #EXTINF:-1,Kanal
            http://sunucu.example.com/1.ts
            """
        let first = M3UParser.parse(text, playlistID: "p1").channels[0]
        let second = M3UParser.parse(text, playlistID: "p2").channels[0]

        XCTAssertNotEqual(first.id, second.id, "Aynı adres iki kaynakta çakışmamalı")
    }

    func test_sortOrderFollowsFileOrder() {
        let result = parse("""
            #EXTINF:-1,Üç
            http://sunucu.example.com/3.ts
            #EXTINF:-1,Bir
            http://sunucu.example.com/1.ts
            """)
        // Listedeki sıra korunur — kullanıcı alıştığı düzeni görür.
        XCTAssertEqual(result.channels.map(\.name), ["Üç", "Bir"])
        XCTAssertEqual(result.channels.map(\.sortOrder), [0, 1])
    }

    // MARK: - Ölçek

    func test_parsesLargePlaylistWithoutDegrading() {
        var text = "#EXTM3U\n"
        let count = 20_000
        for index in 0..<count {
            text += "#EXTINF:-1 tvg-id=\"ch\(index)\" group-title=\"G\(index % 50)\",Kanal \(index)\n"
            text += "http://sunucu.example.com/\(index).ts\n"
        }

        let start = Date()
        let result = parse(text)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(result.channels.count, count)
        XCTAssertEqual(result.categories.count, 50)
        XCTAssertLessThan(elapsed, 15, "20k girişlik liste \(elapsed) sn sürdü — çok yavaş")
    }
}
