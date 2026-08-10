import SwiftUI
import OctopusDomain

/// Bayi kodu girişi.
///
/// ## Bu kod ne işe yarar?
/// Hesap **açmaz** — o iş aktivasyon kodunun. Bu kod uygulamayı bayiye
/// bağlar: markası (ad, renk, logo), duyurusu ve **sunucu listesi** gelir.
/// Sunucu listesi asıl kazanç: kullanıcı `http://sunucu.example.com:8080`
/// gibi bir adresi elle yazmak zorunda kalmaz — IPTV desteğinde en sık
/// karşılaşılan hata yanlış yazılmış sunucu adresidir.
///
/// ⚠️ Kod doğrulanınca ekranın rengi **anında** değişir. Bu bilinçli bir
/// geri bildirim: kullanıcı kodun tuttuğunu bir yazıdan değil, uygulamanın
/// kendisinden görür.
/// ⚠️ DesignSystem'de duruyor çünkü **iki ayrı feature** kullanıyor:
/// karşılama (ilk kurulum) ve ayarlar (bayi değiştirme). Feature'lar
/// birbirini import edemez (CLAUDE.md demir kural 3); ortak bileşenin
/// yeri burası.
public struct ResellerCodeSheet: View {

    /// Kodu panele sorar. `true` → kod bulundu.
    private let onSubmit: (String) async -> Bool
    /// Kayıtlı kod (varsa) — kullanıcı değiştirmek için açmış olabilir.
    private let currentCode: String?

    public init(
        currentCode: String?,
        onSubmit: @escaping (String) async -> Bool
    ) {
        self.currentCode = currentCode
        self.onSubmit = onSubmit
    }

    @Environment(\.dismiss) private var dismiss

    @State private var code: String = ""
    @State private var phase: Phase = .editing
    @FocusState private var isFieldFocused: Bool

    private enum Phase: Equatable {
        case editing
        case checking
        case failed
        case succeeded
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()

                VStack(spacing: Theme.Spacing.lg) {
                    header
                    field
                    statusLine
                    Spacer(minLength: 0)
                    actions
                }
                .padding(Theme.Spacing.xl)
            }
            .navigationTitle("Bayi kodu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Vazgeç") { dismiss() }
                }
            }
        }
        .onAppear {
            code = currentCode ?? ""
            // Klavye kendiliğinden açılır: bu ekranda yapılacak tek şey var.
            isFieldFocused = true
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 40))
                .foregroundColor(Theme.Palette.accent)

            Text("Bayinden aldığın kodu ya da kurulum bağlantısını yapıştır. "
                 + "Uygulama bayinin sunucularını ve görünümünü buradan alır.")
                .font(Theme.Typography.rowSubtitle)
                .foregroundColor(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var field: some View {
        TextField("Örn. 8811", text: $code)
            .focused($isFieldFocused)
            // ⚠️ Otomatik büyük harf ve düzeltme **kapalı**: panel kodları
            // harf de içerebiliyor ve otomatik düzeltme kullanıcının doğru
            // yazdığı kodu sessizce bozuyordu.
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit { submit() }
            .font(.system(.title2, design: .monospaced))
            .multilineTextAlignment(.center)
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(phase == .failed ? Theme.Palette.live : .clear, lineWidth: 1)
            )
            .disabled(phase == .checking)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch phase {
        case .editing:
            // Yer tutucu: satır kaybolup görünürse alttaki düğme zıplar.
            Text(" ").font(Theme.Typography.caption)

        case .checking:
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView().tint(Theme.Palette.accent)
                Text("Kod doğrulanıyor").font(Theme.Typography.caption)
            }
            .foregroundColor(Theme.Palette.textSecondary)

        case .failed:
            Text("Bu kod bulunamadı. Bayinden aldığın kodu kontrol et.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Palette.live)
                .multilineTextAlignment(.center)

        case .succeeded:
            Label("Bayi tanındı", systemImage: "checkmark.circle.fill")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Palette.success)
        }
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button(action: submit) {
                Text("Doğrula")
                    .font(Theme.Typography.rowTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Palette.accent)
            .disabled(phase == .checking || ResellerConfig.normalizeCode(code) == nil)

            // Kayıtlı kod varsa kaldırma yolu da olmalı: bayi değiştiren
            // kullanıcı uygulamayı silmek zorunda kalmamalı.
            if currentCode != nil {
                Button("Bayi bağlantısını kaldır", role: .destructive) {
                    Task {
                        _ = await onSubmit("")
                        dismiss()
                    }
                }
                .font(Theme.Typography.caption)
            }
        }
    }

    private func submit() {
        guard let normalized = ResellerConfig.normalizeCode(code) else { return }

        isFieldFocused = false
        phase = .checking

        Task {
            let isValid = await onSubmit(normalized)
            phase = isValid ? .succeeded : .failed

            guard isValid else { return }
            // Kısa bir an başarı gösterilir; kullanıcı rengin değiştiğini
            // görsün diye hemen kapatılmıyor.
            try? await Task.sleep(for: .milliseconds(600))
            dismiss()
        }
    }
}
