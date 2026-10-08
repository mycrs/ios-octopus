import SwiftUI
import OctopusDomain
import OctopusDesignSystem

struct SampleLibraryOnboardingScreen: View {
    @StateObject private var model: SampleLibraryOnboardingModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    private let onFinished: () -> Void

    init(
        install: @escaping @MainActor () async throws -> Void,
        onFinished: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: SampleLibraryOnboardingModel(install: install))
        self.onFinished = onFinished
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                introduction
                credits
            }
            .padding(Theme.Spacing.lg)
        }
        .safeAreaInset(edge: .bottom) { installAction }
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationTitle("Örnek kütüphane")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Kapat") { dismiss() }
                    .disabled(model.state == .installing)
                    .accessibilityIdentifier("sample-library.close")
            }
        }
        .interactiveDismissDisabled(model.state == .installing)
    }

    private var installAction: some View {
        VStack(spacing: Theme.Spacing.md) {
            if let error = model.errorMessage {
                InlineMessageView(
                    text: AppLocalization.localized(error, locale: locale), kind: .error
                )
            }
            if model.state == .installing {
                ProgressView("Örnek kütüphane hazırlanıyor…")
            }
            OnboardingSubmitButton(
                title: "Örnek kütüphaneyi aç", isEnabled: model.state == .idle
            ) {
                Task {
                    if await model.install() {
                        Haptics.success()
                        onFinished()
                    }
                }
            }
            .accessibilityIdentifier("sample-library.install")
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Palette.background)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Hesap eklemeden özellikleri keşfet")
                .font(Theme.Typography.sectionTitle)
            Text("Açık lisanslı kısa filmlerle oynatıcıyı, favorileri, aramayı ve kaldığın yerden devam etmeyi deneyebilirsin.")
            Text("Örnek TV koleksiyonu kayıtlı filmlerden oluşur; canlı yayın değildir. Rehber, yerel bir örnek programdır.")
            Text("Dizi ekranındaki örnek koleksiyonun bölümleri aynı filmleri içerir.")
            Text("Örnek kütüphane ayrı bir kaynak olarak eklenir. Kişisel kaynakların ve onlara ait favori ve izleme kayıtların korunur. Ayarlar’dan kaynak değiştirebilirsin.")
        }
        .font(Theme.Typography.rowSubtitle)
        .foregroundColor(Theme.Palette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var credits: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Eserler ve lisanslar")
                .font(Theme.Typography.sectionTitle)
            ForEach(SampleLibraryCatalog.credits, id: \.title) { credit in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(credit.title).font(Theme.Typography.rowTitle)
                    Text(credit.creator).font(Theme.Typography.caption)
                    Text(credit.copyrightNotice).font(Theme.Typography.caption)
                    Text(credit.licenseName).font(Theme.Typography.caption)
                    Link("Lisans", destination: credit.licenseURL)
                    Link("Yapım ekibi ve film bilgisi", destination: credit.creditsURL)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Filmler, orijinal jenerikleriyle oynatılır. İnternet bağlantısı gerekir.")
                .font(Theme.Typography.caption)
        }
        .foregroundColor(Theme.Palette.textSecondary)
        .padding(Theme.Spacing.lg)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }
}
