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
        // Panel yapılandırması ekran açıldıktan sonra da gelebilir;
        // kapatılmış bir form seçili kalmasın.
        .onAppear { viewModel.reconcileSourceKind() }
        .task { await viewModel.loadResellerServers() }
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

    /// ⚠️ Tek seçenek kalınca seçici **hiç çizilmiyor**: bayi elle girişi
    /// kapattığında geriye yalnızca aktivasyon kodu kalır ve tek düğmeli
    /// bir segment kontrolü, olmayan bir seçim varmış gibi görünür.
    @ViewBuilder
    private var sourcePicker: some View {
        let kinds = viewModel.availableSourceKinds

        if kinds.count > 1 {
            Picker("Kaynak türü", selection: $viewModel.sourceKind) {
                ForEach(kinds) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.step.isBusy)
        }
    }

    @ViewBuilder
    private var fields: some View {
        VStack(spacing: Theme.Spacing.md) {
            switch viewModel.sourceKind {
            case .activationCode:
                FormFieldView(
                    title: "Aktivasyon kodu",
                    placeholder: "ABC-1234",
                    text: $viewModel.activationCode
                )
                .focused($focusedField, equals: .code)

                InlineMessageView(
                    text: "Bayinden aldığın kodu gir. Sunucu adresi ve parola otomatik ayarlanır.",
                    kind: .info
                )

            case .xtream:
                resellerServerPicker

                FormFieldView(
                    title: "Sunucu adresi",
                    // Bayi sunucusu varsa alan boş bırakılabilir; hepsi denenir.
                    placeholder: viewModel.resellerServers.isEmpty
                        ? "panel.example.com:8080"
                        : "boş bırakırsan hepsi denenir",
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

            // Kod ile girişte ad panelden gelir; kullanıcıya sorulmaz.
            if viewModel.sourceKind != .activationCode {
                FormFieldView(
                    title: "Kaynak adı",
                    placeholder: "isteğe bağlı",
                    text: $viewModel.name
                )
                .focused($focusedField, equals: .name)
            }
        }
        .disabled(viewModel.step.isBusy)
    }

    /// Bayinin sunucuları — varsa adres yazmaya gerek kalmaz.
    ///
    /// ⚠️ Liste boşsa **hiç çizilmiyor**: bayi kodu girmemiş kullanıcıya
    /// boş bir "sunucu seç" başlığı göstermek, eksik bir şey varmış
    /// izlenimi verirdi.
    @ViewBuilder
    private var resellerServerPicker: some View {
        if !viewModel.resellerServers.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Bayinin sunucuları")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textSecondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(viewModel.resellerServers) { server in
                            serverChip(server)
                        }
                    }
                    .padding(.horizontal, 1)   // kenardaki gölge kırpılmasın
                }
            }
        }
    }

    private func serverChip(_ server: ResellerServer) -> some View {
        let isSelected = viewModel.selectedServerID == server.id

        return Button {
            viewModel.select(server: server)
            focusedField = .username   // adres hazır; sıradaki alana geç
        } label: {
            Text(server.displayName)
                .font(Theme.Typography.caption)
                .foregroundColor(isSelected ? Theme.Palette.accent : Theme.Palette.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(isSelected ? Theme.Palette.accentMuted : Theme.Palette.surface)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
