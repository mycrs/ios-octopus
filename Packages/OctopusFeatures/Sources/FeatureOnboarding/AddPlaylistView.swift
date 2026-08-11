import SwiftUI
import OctopusDomain
import OctopusDesignSystem

/// Kaynak ekleme formu.
public struct AddPlaylistView: View {

    @StateObject private var viewModel: AddPlaylistViewModel
    private let onFinished: () -> Void

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case code, host, username, password, url, epg, name
    }

    public init(dependencies: OnboardingDependencies, onFinished: @escaping () -> Void) {
        let model = AddPlaylistViewModel(dependencies: dependencies)
#if DEBUG
        if OnboardingDebugLaunch.opensForm {
            model.sourceKind = OnboardingDebugLaunch.showsResellerQuickLogin
                ? .xtream
                : .activationCode
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
                SyncOverlayView(step: displayedStep)
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
        .task {
#if DEBUG
            if OnboardingDebugLaunch.showsResellerQuickLogin {
                viewModel.prepareDebugResellerQuickLogin()
                return
            }
#endif
            await viewModel.prepareXtreamLogin()
        }
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
                    text: "Bayinden aldığın kodu gir. Sunucu adresi ve parola otomatik ayarlanır.",
                    kind: .info
                )

            case .xtream:
                FormFieldView(
                    title: "DNS adresi veya bayi kodu",
                    placeholder: "http://panel.example.com:8080 veya 8811",
                    text: $viewModel.host,
                    icon: viewModel.isResellerCodeInput ? "person.badge.key.fill" : "network",
                    contentType: .URL
                )
                .focused($focusedField, equals: .host)

                if viewModel.isResellerCodeInput {
                    ResellerQuickLoginIntro()
                }

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
        .background(Theme.Palette.surface.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.sourceKind)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isResellerCodeInput)
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
}
