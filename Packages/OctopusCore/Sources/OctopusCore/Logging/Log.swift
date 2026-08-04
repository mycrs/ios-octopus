import Foundation
import os

/// Merkezi loglama. `print` yerine her zaman bunu kullan.
///
/// Kategori bazlı ayrım sayesinde Console.app'te filtreleyebilirsin:
/// `subsystem: com.octopus.iptv`
public enum Log {

    private static let subsystem = "com.octopus.iptv"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let database = Logger(subsystem: subsystem, category: "database")
    public static let parser = Logger(subsystem: subsystem, category: "parser")
    public static let playback = Logger(subsystem: subsystem, category: "playback")
    public static let sync = Logger(subsystem: subsystem, category: "sync")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}
