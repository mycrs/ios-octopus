import SwiftUI
import OctopusDomain

/// Tüm gezinme durumunun tek sahibi.
///
/// Feature modülleri birbirini import edemez; bir ekrandan diğerine geçiş
/// **yalnızca** buradan yapılır:
/// ```swift
/// router.push(.movieDetail(movie.id))
/// ```
/// `FeatureLive`, `FeaturePlayer`'ın var olduğunu bile bilmez.
@MainActor
public final class AppRouter: ObservableObject {

    /// Aktif sekme. Aynı sekmeye tekrar dokunmak kökene döner (iOS alışkanlığı).
    @Published public var selectedTab: AppTab {
        didSet {
            if oldValue == selectedTab { popToRoot(in: selectedTab) }
        }
    }

    /// Uygulamanın hangi sekmeyle açılacağı.
    ///
    /// Referans projede herkes ana sayfadan karşılanıyordu ama kullanıcıların
    /// çoğu doğrudan Canlı TV'ye geçiyordu — her açılışta bir dokunuş israfı.
    @Published public var startupTab: AppTab {
        didSet { store.set(startupTab.rawValue, forKey: Self.startupTabKey) }
    }

    private let store: UserDefaults
    private static let startupTabKey = "startup.tab"

    /// Her sekmenin kendi gezinme yığını vardır — sekme değişince yığın korunur.
    @Published public var paths: [AppTab: NavigationPath] = [:]

    @Published public var sheet: AppSheet?
    @Published public var player: PlayerPresentation?

    /// Kaynak yoksa onboarding gösterilir. App başlangıçta belirler.
    @Published public var needsOnboarding: Bool = false

    public init(store: UserDefaults = .standard) {
        self.store = store

        // Kayıtlı tercih geçersizse (sekme kaldırılmış olabilir) ana sayfaya düşer.
        let saved = store.string(forKey: Self.startupTabKey).flatMap(AppTab.init(rawValue:))
        let tab = saved.map { AppTab.startupOptions.contains($0) ? $0 : .home } ?? .home

        self.startupTab = tab
        self.selectedTab = tab
    }

    // MARK: - Yığın işlemleri

    public func push(_ route: AppRoute, in tab: AppTab? = nil) {
        let target = tab ?? selectedTab
        var path = paths[target] ?? NavigationPath()
        path.append(route)
        paths[target] = path
    }

    public func pop(in tab: AppTab? = nil) {
        let target = tab ?? selectedTab
        guard var path = paths[target], !path.isEmpty else { return }
        path.removeLast()
        paths[target] = path
    }

    public func popToRoot(in tab: AppTab? = nil) {
        paths[tab ?? selectedTab] = NavigationPath()
    }

    /// Sekme değiştirip aynı anda gezinmek için (ör. arama sonucundan filme).
    public func switchTab(to tab: AppTab, then route: AppRoute? = nil) {
        selectedTab = tab
        if let route { push(route, in: tab) }
    }

    /// `NavigationStack(path:)` için bağlama.
    public func binding(for tab: AppTab) -> Binding<NavigationPath> {
        Binding(
            get: { [weak self] in self?.paths[tab] ?? NavigationPath() },
            set: { [weak self] newValue in self?.paths[tab] = newValue }
        )
    }

    // MARK: - Oynatıcı

    public func presentPlayer(_ source: PlaybackItem.Source, startAt: TimeInterval? = nil) {
        player = PlayerPresentation(source: source, startAt: startAt)
    }

    public func dismissPlayer() {
        player = nil
    }

    // MARK: - Modal

    public func present(_ sheet: AppSheet) {
        self.sheet = sheet
    }

    public func dismissSheet() {
        sheet = nil
    }

    /// Açık ekranları kapatır ama sekme seçimini korur.
    ///
    /// Ebeveyn kilidi kurulduğunda gerekir: kullanıcı yetişkin bir içeriğin
    /// detayındayken Ayarlar'a geçip PIN kurmuş olabilir. Listeler süzülür
    /// ama **yığında duran** ekran kimliğiyle açık kalır ve geri dönünce
    /// karşısına çıkardı.
    public func clearOpenScreens() {
        paths = [:]
        player = nil
    }

    /// Kaynak silindi/değişti — tüm yığınları temizle, eski id'lerle ekran açık kalmasın.
    public func resetAfterPlaylistChange() {
        paths = [:]
        player = nil
        sheet = nil
        selectedTab = startupTab
    }
}
