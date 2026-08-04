import Foundation
import GRDB
import OctopusCore
import OctopusDomain

/// SQLite veritabanının sahibi. Tüm kalıcılık buradan geçer.
///
/// ⚠️ GRDB bu modülün dışına **sızmaz**. Repository'ler bu tipi kullanır,
/// dışarıya yalnızca Domain protokolleri görünür.
public final class AppDatabase {

    /// Okuma/yazma erişimi. Üretimde `DatabasePool` (WAL, eşzamanlı okuma),
    /// testlerde bellek içi `DatabaseQueue`.
    let writer: any DatabaseWriter

    /// - Parameter writer: Hazır bir bağlantı. Migration burada uygulanır.
    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        do {
            try Self.migrator.migrate(writer)
        } catch {
            // Referans projede cache hataları sessizce yutulduğu için
            // 14k kanallık hesapta cache'in HİÇ çalışmadığı aylarca fark edilmedi.
            // Kalıcılık hataları burada asla sessiz kalmaz.
            Log.database.error("Migration başarısız: \(String(describing: error))")
            throw AppError.storage(reason: "Veritabanı hazırlanamadı")
        }
        Log.database.info("Veritabanı hazır — şema sürümü güncel")
    }

    /// Uygulama için kalıcı veritabanı açar.
    ///
    /// Dosya `Application Support/Octopus/octopus.sqlite` altında tutulur;
    /// iCloud yedeklemesinden hariç tutulur (içerik yeniden indirilebilir,
    /// kullanıcının yedek kotasını şişirmesine gerek yok).
    public static func makeShared(fileManager: FileManager = .default) throws -> AppDatabase {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folderURL = baseURL.appendingPathComponent("Octopus", isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        var databaseURL = folderURL.appendingPathComponent("octopus.sqlite")
        let pool = try DatabasePool(path: databaseURL.path, configuration: makeConfiguration())

        // Katalog her an sunucudan yeniden çekilebilir → yedeklemeye gerek yok.
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? databaseURL.setResourceValues(resourceValues)

        return try AppDatabase(pool)
    }

    /// Testler ve SwiftUI önizlemeleri için bellek içi veritabanı.
    public static func makeInMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: makeConfiguration()))
    }

    static func makeConfiguration() -> Configuration {
        var config = Configuration()

        // Senkronizasyon yazarken UI okuma yapıyor olabilir; kilit beklemesi
        // anında hata vermek yerine kısa süre denesin.
        config.busyMode = .timeout(5)

        // Yabancı anahtarlar açık: kaynak silinince tüm içeriği cascade ile gider.
        config.foreignKeysEnabled = true

        #if DEBUG
        config.prepareDatabase { db in
            db.trace { event in
                Log.database.debug("SQL: \(event.description, privacy: .public)")
            }
        }
        #endif

        return config
    }
}

// MARK: - Erişim yardımcıları

extension AppDatabase {

    /// Yazma işlemi. Hatalar loglanır ve `AppError.storage`'a çevrilir.
    func write<T>(_ updates: @Sendable (Database) throws -> T) async throws -> T {
        do {
            return try await writer.write(updates)
        } catch {
            Log.database.error("Yazma hatası: \(String(describing: error))")
            throw AppError.storage(reason: String(describing: error))
        }
    }

    /// Okuma işlemi.
    func read<T>(_ value: @Sendable (Database) throws -> T) async throws -> T {
        do {
            return try await writer.read(value)
        } catch {
            Log.database.error("Okuma hatası: \(String(describing: error))")
            throw AppError.storage(reason: String(describing: error))
        }
    }
}
