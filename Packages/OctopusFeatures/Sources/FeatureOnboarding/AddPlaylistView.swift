import SwiftUI
import OctopusDomain
import OctopusDesignSystem

/// Kaynak ekleme formu.
public struct AddPlaylistView: View {

    @StateObject private var viewModel: AddPlaylistViewModel
    private let onFinished: () -> Void
    @Environment(\.brandColor) private var brandColor
    @Environment(\.locale) private var locale
    @EnvironmentObject private var theme: ThemeController

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case code, host, resellerCode, username, password, url, epg, name
    }

    public init(dependencies: OnboardingDependencies, onFinished: @escaping () -> Void) {
        let model = AddPlaylistViewModel(dependencies: dependencies)
#if DEBUG
        if OnboardingDebugLaunch.opensForm {
            model.sourceKind = .activationCode
        }
#endif
        _viewModel = StateObject(wrappedValue: model)
        self.onFinished = onFinished
    }

    public var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()
            OnboardingBackgroundGlow(opacity: 0.13, center: .topTrailing, endRadius: 380)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                    sourcePicker
                    fields
                    if let errorMessage = viewModel.errorMessage {
                        InlineMessageView(text: errorMessage, kind: .error)
                    }
                    submitButton
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.xl)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)

            if displayedStep.isBusy {
                SyncOverlayView(
                    step: displayedStep,
                    counts: displayedCounts,
                    brandName: theme.resellerName ?? "Octopus",
                    logoURL: theme.logoURL
                )
            }
        }
        .onChange(of: viewModel.step) { step in
            if step == .done {
                Haptics.success()
                onFinished()
            }
        }
        .onChange(of: viewModel.errorMessage) { message in
            if message != nil { Haptics.warning() }
        }
        // Panel yapılandırması ekran açıldıktan sonra da gelebilir;
        // kapatılmış bir form seçili kalmasın.
        .onAppear { viewModel.reconcileSourceKind() }
    }

    // MARK: - Bölümler

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            OnboardingHeroHeader()

            Text("Aboneliğinin bilgilerini gir. Kaydetmeden önce bağlantı sınanır.")
                .font(Theme.Typography.rowSubtitle)
                .foregroundColor(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// ⚠️ Tek seçenek kalınca seçici **hiç çizilmiyor**: bayi elle girişi
    /// kapattığında geriye yalnızca aktivasyon kodu kalır ve tek düğmeli
    /// bir segment kontrolü, olmayan bir seçim varmış gibi görünür.
    @ViewBuilder
    private var sourcePicker: some View {
        let kinds = viewModel.availableSourceKinds

        if kinds.count > 1 {
            OnboardingSourcePicker(kinds: kinds, selection: $viewModel.sourceKind)
            .disabled(viewModel.step.isBusy)
        }
    }

    /// Xtream sekmesindeki alt seçim: DNS mi, kısa kod mu.
    ///
    /// ⚠️ `OnboardingSourcePicker`'ın küçük bir kopyası değil — kasıtlı.
    /// Üstteki seçici **kaynak türünü** seçtiriyor (Xtream/M3U/Kod), bu ise
    /// Xtream içinde **giriş biçimini**. İkisini aynı bileşenle çizmek
    /// hiyerarşiyi bulanıklaştırırdı; bu yüzden daha sade, girintili bir
    /// satır olarak duruyor.
    private var xtreamEntryModePicker: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(AddPlaylistViewModel.XtreamEntryMode.allCases) { mode in
                let isSelected = viewModel.xtreamEntryMode == mode

                Button {
                    guard viewModel.xtreamEntryMode != mode else { return }
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.18)) {
                        viewModel.xtreamEntryMode = mode
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(AppLocalization.localized(mode.title, locale: locale))
                            .font(Theme.Typography.caption.weight(.semibold))
                    }
                    .foregroundColor(isSelected ? brandColor : Theme.Palette.textSecondary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .frame(height: 34)
                    .background(isSelected ? brandColor.opacity(0.14) : .clear)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().stroke(
                            isSelected ? brandColor.opacity(0.4) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .disabled(viewModel.step.isBusy)
    }

    /// Seçili giriş biçimine göre gösterilen alan.
    @ViewBuilder
    private var xtreamAddressField: some View {
        if viewModel.xtreamEntryMode == .dns {
            FormFieldView(
                // ⚠️ "DNS adresi" değil: DNS bir ad çözümleme sistemidir,
                // girilen şey sunucunun adresi. Sektörde yaygın olsa da
                // yanlış terim, uygulamayı amatör gösteriyor ve
                // İngilizcede hiç anlaşılmıyor.
                //
                // ⚠️ Bu alan **her zaman yazıldığı gibi** kullanılır.
                // Eskiden dört haneli bir giriş burada gizlice kısa koda
                // dönüşüyordu; App Review bunu "gizlenmiş özellik" sayıp
                // reddetti. Kısa kod artık yan sekmede, kendi etiketli
                // alanında.
                title: "Sunucu adresi",
                placeholder: "http://panel.example.com:8080",
                text: $viewModel.host,
                icon: "network",
                contentType: .URL
            )
            .focused($focusedField, equals: .host)
        } else {
            FormFieldView(
                title: "Kısa kod",
                placeholder: "1234",
                text: $viewModel.resellerCode,
                icon: "number"
            )
            .focused($focusedField, equals: .resellerCode)

            InlineMessageView(
                text: "Hizmet sağlayıcından aldığın kısa kod, sunucu adresinin yerine geçer.",
                kind: .info
            )
        }
    }

    @ViewBuilder
    private var fields: some View {
        VStack(spacing: Theme.Spacing.md) {
            switch viewModel.sourceKind {
            case .activationCode:
                ActivationCodeIntro()

                FormFieldView(
                    title: "Aktivasyon kodu",
                    placeholder: "ABC-1234",
                    text: $viewModel.activationCode,
                    icon: "key.horizontal.fill"
                )
                .focused($focusedField, equals: .code)

                InlineMessageView(
                    text: "Kodun doğrulandığında hesabın otomatik olarak hazırlanır.",
                    kind: .info
                )

                QuickSetupLink()

            case .xtream:
                xtreamEntryModePicker
                xtreamAddressField

                FormFieldView(
                    title: "Kullanıcı adı",
                    placeholder: "kullanıcı adın",
                    text: $viewModel.username,
                    icon: "person.fill",
                    contentType: .username
                )
                .focused($focusedField, equals: .username)

                FormFieldView(
                    title: "Parola",
                    placeholder: "parolan",
                    text: $viewModel.password,
                    icon: "lock.fill",
                    isSecure: true,
                    contentType: .password
                )
                .focused($focusedField, equals: .password)

            case .m3u:
                FormFieldView(
                    title: "M3U bağlantısı",
                    placeholder: "http://example.com/liste.m3u",
                    text: $viewModel.m3uURL,
                    icon: "link",
                    contentType: .URL
                )
                .focused($focusedField, equals: .url)

                FormFieldView(
                    title: "EPG bağlantısı",
                    placeholder: "isteğe bağlı",
                    text: $viewModel.epgURL,
                    icon: "calendar",
                    contentType: .URL
                )
                .focused($focusedField, equals: .epg)
            }

            // Kod ile girişte ad panelden gelir; kullanıcıya sorulmaz.
            if viewModel.sourceKind != .activationCode {
                FormFieldView(
                    title: "Kaynak adı",
                    placeholder: "isteğe bağlı",
                    text: $viewModel.name,
                    icon: "tag.fill"
                )
                .focused($focusedField, equals: .name)
            }
        }
        .padding(Theme.Spacing.lg)
        .background {
            LinearGradient(
                colors: [brandColor.opacity(0.055), Theme.Palette.surface.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .stroke(brandColor.opacity(0.14), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.sourceKind)
        .disabled(viewModel.step.isBusy)
    }

    private var submitButton: some View {
        OnboardingSubmitButton(
            title: viewModel.sourceKind == .activationCode
                ? "Kodu doğrula"
                : "Kaydet ve içeriği getir",
            isEnabled: viewModel.canSubmit
        ) {
            focusedField = nil
            Task { await viewModel.submit() }
        }
    }

    private var displayedStep: AddPlaylistViewModel.Step {
#if DEBUG
        if let step = OnboardingDebugLaunch.forcedStep { return step }
#endif
        return viewModel.step
    }

    private var displayedCounts: SyncContentCounts {
#if DEBUG
        if let counts = OnboardingDebugLaunch.forcedCounts { return counts }
#endif
        return viewModel.syncCounts
    }
}
