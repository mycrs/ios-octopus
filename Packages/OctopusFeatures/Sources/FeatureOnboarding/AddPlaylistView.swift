import SwiftUI
import OctopusDomain
import OctopusDesignSystem

/// Kaynak ekleme formu.
public struct AddPlaylistView: View {

    @StateObject private var viewModel: AddPlaylistViewModel
    private let onFinished: () -> Void

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case host, username, password, url, epg, name
    }

    public init(dependencies: OnboardingDependencies, onFinished: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: AddPlaylistViewModel(dependencies: dependencies))
        self.onFinished = onFinished
    }

    public var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

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
                .padding(Theme.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)

            if viewModel.step.isBusy {
                SyncOverlayView(step: viewModel.step)
            }
        }
        .onChange(of: viewModel.step) { step in
            if step == .done { onFinished() }
        }
    }

    // MARK: - Bölümler

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Kaynak ekle")
                .font(Theme.Typography.screenTitle)
                .foregroundColor(Theme.Palette.textPrimary)
            Text("Aboneliğinin bilgilerini gir. Kaydetmeden önce bağlantı sınanır.")
                .font(Theme.Typography.rowSubtitle)
                .foregroundColor(Theme.Palette.textSecondary)
        }
    }

    private var sourcePicker: some View {
        Picker("Kaynak türü", selection: $viewModel.sourceKind) {
            ForEach(AddPlaylistViewModel.SourceKind.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .disabled(viewModel.step.isBusy)
    }

    @ViewBuilder
    private var fields: some View {
        VStack(spacing: Theme.Spacing.md) {
            switch viewModel.sourceKind {
            case .xtream:
                FormFieldView(
                    title: "Sunucu adresi",
                    placeholder: "panel.example.com:8080",
                    text: $viewModel.host,
                    contentType: .URL
                )
                .focused($focusedField, equals: .host)

                FormFieldView(
                    title: "Kullanıcı adı",
                    placeholder: "kullanıcı adın",
                    text: $viewModel.username,
                    contentType: .username
                )
                .focused($focusedField, equals: .username)

                FormFieldView(
                    title: "Parola",
                    placeholder: "parolan",
                    text: $viewModel.password,
                    isSecure: true
                )
                .focused($focusedField, equals: .password)

            case .m3u:
                FormFieldView(
                    title: "M3U bağlantısı",
                    placeholder: "http://example.com/liste.m3u",
                    text: $viewModel.m3uURL,
                    contentType: .URL
                )
                .focused($focusedField, equals: .url)

                FormFieldView(
                    title: "EPG bağlantısı",
                    placeholder: "isteğe bağlı",
                    text: $viewModel.epgURL,
                    contentType: .URL
                )
                .focused($focusedField, equals: .epg)
            }

            FormFieldView(
                title: "Kaynak adı",
                placeholder: "isteğe bağlı",
                text: $viewModel.name
            )
            .focused($focusedField, equals: .name)
        }
        .disabled(viewModel.step.isBusy)
    }

    private var submitButton: some View {
        Button {
            focusedField = nil
            Task { await viewModel.submit() }
        } label: {
            Text("Kaydet ve içeriği getir")
                .font(Theme.Typography.rowTitle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.Palette.accent)
        .disabled(!viewModel.canSubmit)
    }
}
