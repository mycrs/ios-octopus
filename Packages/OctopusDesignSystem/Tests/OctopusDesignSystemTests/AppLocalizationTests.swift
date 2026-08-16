import XCTest
@testable import OctopusDesignSystem

/// `AppLocalization`'ın ters-ayrıştırıcısı.
///
/// ⚠️ Bu 130 satır bugüne kadar **hiç test edilmemişti**: eşleme mantığı
/// `Bundle.main` okumasıyla iç içeydi ve paket testinde `Bundle.main`
/// uygulama paketi olmadığı için İngilizce yol hiç çalışmıyordu. Saf eşleme
/// `dynamicFormat(for:)` olarak ayrılınca test edilebilir hâle geldi.
///
/// Test edilen şey **davranışın kilidi**: ViewModel'ler biçimlenmiş Türkçe
/// metin üretiyor, burası sayıyı/metni geri söküp çeviri anahtarına
/// çeviriyor. Bir üretici biçimini değiştirirse (ör. "3 sezon" → "3 Sezon")
/// eşleme sessizce düşer ve İngilizce'de Türkçe metin kalır — testler bunu
/// yakalar.
final class AppLocalizationTests: XCTestCase {

    private typealias Argument = AppLocalization.FormatArgument

    private func match(_ key: String) -> (formatKey: String, arguments: [Argument])? {
        AppLocalization.dynamicFormat(for: key)
    }

    // MARK: - Tek sayılı kalıplar

    func test_singleNumberSuffixes() {
        let cases: [(input: String, key: String, number: Int)] = [
            ("3 sezon", "%ld sezon", 3),
            ("42 bölüm", "%ld bölüm", 42),
            ("359 gün kaldı", "%ld gün kaldı", 359),
            ("5 dakika önce", "%ld dakika önce", 5),
            ("2 saat önce", "%ld saat önce", 2),
            ("7 gün önce", "%ld gün önce", 7),
            ("32 dk", "%ld dk", 32),
            ("2 sa", "%ld sa", 2)
        ]

        for testCase in cases {
            let result = match(testCase.input)
            XCTAssertEqual(result?.formatKey, testCase.key, "girdi: \(testCase.input)")
            XCTAssertEqual(result?.arguments, [.number(testCase.number)], "girdi: \(testCase.input)")
        }
    }

    func test_longerSuffixWinsOverShorterOne() {
        // "5 dakika önce güncellendi" hem " dakika önce güncellendi" hem de
        // " dakika önce" ile bitiyor. Sıra bozulursa "güncellendi" kaybolur.
        let result = match("5 dakika önce güncellendi")
        XCTAssertEqual(result?.formatKey, "%ld dakika önce güncellendi")
        XCTAssertEqual(result?.arguments, [.number(5)])
    }

    // MARK: - Süre biçimleri

    func test_spacedDuration() {
        // LiveChannelsViewModel: "1 sa 5 dk"
        let result = match("1 sa 5 dk")
        XCTAssertEqual(result?.formatKey, "%ld sa %ld dk")
        XCTAssertEqual(result?.arguments, [.number(1), .number(5)])
    }

    func test_compactDuration() {
        // MovieDetailViewModel: "2s 15dk" — araya boşluk koymayan ayrı bir biçim.
        let result = match("2s 15dk")
        XCTAssertEqual(result?.formatKey, "%ld sa %ld dk")
        XCTAssertEqual(result?.arguments, [.number(2), .number(15)])
    }

    func test_compactMinutesOnly() {
        // MovieDetailViewModel saatsiz hâl: "45dk"
        let result = match("45dk")
        XCTAssertEqual(result?.formatKey, "%ld dk")
        XCTAssertEqual(result?.arguments, [.number(45)])
    }

    // MARK: - İz ve sezon numaraları

    func test_numberedTracks() {
        XCTAssertEqual(match("Ses 2")?.formatKey, "Ses %ld")
        XCTAssertEqual(match("Ses 2")?.arguments, [.number(2)])
        XCTAssertEqual(match("Altyazı 1")?.formatKey, "Altyazı %ld")
        XCTAssertEqual(match("Altyazı 1")?.arguments, [.number(1)])
    }

    func test_seasonNumber() {
        let result = match("3. Sezon")
        XCTAssertEqual(result?.formatKey, "%ld. Sezon")
        XCTAssertEqual(result?.arguments, [.number(3)])
    }

    // MARK: - Metin taşıyan kalıplar

    func test_textSuffixPatterns() {
        let cases: [(input: String, key: String, text: String)] = [
            ("S01B02 — devam et", "%@ — devam et", "S01B02"),
            ("S01B02 oynat", "%@ oynat", "S01B02"),
            ("Türkçe · Seçili", "%@ · Seçili", "Türkçe"),
            ("TRT 1, canlı yayın", "%@, canlı yayın", "TRT 1")
        ]

        for testCase in cases {
            let result = match(testCase.input)
            XCTAssertEqual(result?.formatKey, testCase.key, "girdi: \(testCase.input)")
            XCTAssertEqual(result?.arguments, [.text(testCase.text)], "girdi: \(testCase.input)")
        }
    }

    func test_textPrefixPatterns() {
        XCTAssertEqual(match("Oynatılıyor: TRT 1")?.arguments, [.text("TRT 1")])
        XCTAssertEqual(match("Puan 8.4")?.arguments, [.text("8.4")])
    }

    // MARK: - Eşleşmeyenler

    func test_contentNamesAreNotMangled() {
        // ⚠️ En önemli olumsuz durum: içerik adları çeviri anahtarı değildir
        // ve olduğu gibi geçmelidir. Kalıplardan biri fazla geniş olsaydı
        // film/kanal adları bozulurdu.
        for name in ["Karanlık Orman", "TRT 1", "Beyaz Gece", "Altın Anahtar"] {
            XCTAssertNil(match(name), "içerik adı eşleşmemeli: \(name)")
        }
    }

    func test_numberlessLookalikesDoNotMatch() {
        // Sayı yerine metin varsa eşleşme olmamalı — `Int()` başarısız olunca
        // döngü `continue` ile sıradaki kalıba geçer, yanlış anahtar üretmez.
        XCTAssertNil(match("birkaç sezon"))
        XCTAssertNil(match("son bölüm"))
    }
}
