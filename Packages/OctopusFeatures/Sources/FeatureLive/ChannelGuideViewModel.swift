import Foundation
import Combine
import OctopusDomain
import OctopusDesignSystem

/// Bir kanalın yayın akışı (EPG).
///
/// Mobilde TV tarzı zaman ızgarası yerine **dikey liste** kullanılıyor:
/// dar ekranda yatay kaydırmalı ızgara okunmuyor, kullanıcı zaten tek
/// kanalın akışını merak ediyor.
@MainActor
public final class ChannelGuideViewModel: ObservableObject {

    /// Listede gösterilecek program ve durumu.
    public struct Entry: Identifiable, Equatable {
        public let id: String
        public let program: EPGProgram
        public let isOnAir: Bool
        public let hasEnded: Bool
        /// Yalnızca yayındaki program için (0...1).
        public let progress: Double?
    }

    @Published public private(set) var channel: Channel?
    @Published public private(set) var entries: [Entry] = []
    @Published public private(set) var state: LoadableState<Int> = .idle
    /// Gün kaydırma: 0 = bugün, 1 = yarın, -1 = dün.
    @Published public private(set) var dayOffset = 0

    private let channelID: Channel.ID
    private let dependencies: LiveDependencies
    private let now: () -> Date
    private let calendar: Calendar

    public init(
        channelID: Channel.ID,
        dependencies: LiveDependencies,
        now: @escaping () -> Date = Date.init
    ) {
        self.channelID = channelID
        self.dependencies = dependencies
        self.now = now

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "tr_TR")
        self.calendar = calendar
    }

    public func load() async {
        state = .loading

        do {
            guard let found = try await dependencies.channels.channel(id: channelID) else {
                state = .failed(.notFound)
                return
            }
            channel = found
            await loadPrograms()
        } catch {
            state = .failed(AppError.wrap(error))
        }
    }

    public func changeDay(by delta: Int) async {
        dayOffset += delta
        await loadPrograms()
    }

    private func loadPrograms() async {
        guard let epgID = channel?.epgChannelID else {
            // Kanalın rehber kimliği yoksa akış gösterilemez; bu bir hata
            // değil, yaygın bir eksiklik.
            entries = []
            state = .loaded(0)
            return
        }

        let current = now()
        let dayStart = calendar.startOfDay(for: current)
            .addingTimeInterval(Double(dayOffset) * 86_400)
        let dayEnd = dayStart.addingTimeInterval(86_400)

        do {
            let programs = try await dependencies.epg.programs(
                epgChannelID: epgID,
                from: dayStart,
                to: dayEnd
            )
            entries = programs.map { program in
                Entry(
                    id: program.id.value,
                    program: program,
                    isOnAir: program.isOnAir(at: current),
                    hasEnded: program.endDate <= current,
                    progress: program.isOnAir(at: current) ? program.progress(at: current) : nil
                )
            }
            state = .loaded(entries.count)
        } catch {
            state = .failed(AppError.wrap(error))
        }
    }

    // MARK: - Sunum

    /// Gün başlığı: "Bugün", "Yarın", "Dün" veya tarih.
    public var dayTitle: String {
        switch dayOffset {
        case 0: return "Bugün"
        case 1: return "Yarın"
        case -1: return "Dün"
        default:
            let date = calendar.startOfDay(for: now())
                .addingTimeInterval(Double(dayOffset) * 86_400)
            return Self.dayFormatter.string(from: date)
        }
    }

    /// Rehber verisi yalnızca sınırlı bir aralığı kapsar; kullanıcı boş
    /// günlere doğru sonsuz kaydırmamalı.
    public var canGoBack: Bool { dayOffset > -1 }
    public var canGoForward: Bool { dayOffset < 6 }

    public var selectedDate: Date {
        calendar.startOfDay(for: now())
            .addingTimeInterval(Double(dayOffset) * 86_400)
    }

    public func timeText(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMMM EEEE"
        return formatter
    }()
}
