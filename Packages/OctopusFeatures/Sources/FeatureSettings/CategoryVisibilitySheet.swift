import SwiftUI
import OctopusDomain
import OctopusDesignSystem

/// Kategori görünürlüğü yalnızca PIN ile açılmış oturumdan erişilir.
/// Gizlenen kategori; katalog, arama, favoriler ve oynatıcı listelerinden kalkar.
struct CategoryVisibilitySheet: View {

    @ObservedObject var viewModel: SettingsViewModel
    @EnvironmentObject private var language: LanguageController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.brandColor) private var brandColor

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()

                if viewModel.contentCategories.isEmpty {
                    EmptyStateView(
                        icon: "rectangle.3.group",
                        title: "Kategori bulunamadı",
                        message: "Önce kaynağını güncellemeyi dene."
                    )
                } else {
                    List {
                        ForEach(MediaCategory.Kind.allCases, id: \.self) { kind in
                            let categories = categories(for: kind)
                            if !categories.isEmpty {
                                Section {
                                    ForEach(categories) { category in
                                        Toggle(
                                            isOn: Binding(
                                                get: { viewModel.isCategoryVisible(category) },
                                                set: { visible in
                                                    Task {
                                                        await viewModel.setCategory(
                                                            category,
                                                            visible: visible
                                                        )
                                                    }
                                                }
                                            )
                                        ) {
                                            Text(category.name)
                                                .foregroundColor(Theme.Palette.textPrimary)
                                        }
                                        .tint(brandColor)
                                    }
                                } header: {
                                    HStack {
                                        Text(title(for: kind))
                                        Spacer()
                                        Menu {
                                            Button("Tümünü göster") {
                                                Task {
                                                    await viewModel.setAllCategories(
                                                        kind: kind,
                                                        visible: true
                                                    )
                                                }
                                            }
                                            Button("Tümünü gizle", role: .destructive) {
                                                Task {
                                                    await viewModel.setAllCategories(
                                                        kind: kind,
                                                        visible: false
                                                    )
                                                }
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis.circle")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Kategori görünürlüğü")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                }
            }
        }
    }

    private func categories(for kind: MediaCategory.Kind) -> [MediaCategory] {
        viewModel.contentCategories.filter { $0.kind == kind }
    }

    private func title(for kind: MediaCategory.Kind) -> String {
        switch kind {
        case .live: return language.localized("Canlı TV")
        case .movie: return language.localized("Filmler")
        case .series: return language.localized("Diziler")
        }
    }
}
