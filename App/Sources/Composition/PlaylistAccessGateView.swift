import SwiftUI
import OctopusDesignSystem

/// Hızlı kurulumda PIN ile korunan listenin uygulama giriş kapısı.
struct PlaylistAccessGateView: View {

    let playlistName: String?
    let logoURL: URL?
    let brandName: String
    let onUnlock: (String) async -> Bool
    let onManageSources: () -> Void

    @State private var pin = ""
    @State private var isChecking = false
    @State private var errorMessage: String?
    @Environment(\.brandColor) private var brandColor

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            Circle()
                .fill(brandColor.opacity(0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 90)
                .offset(y: -300)

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    brand

                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundColor(brandColor)
                            .frame(width: 68, height: 68)
                            .background(brandColor.opacity(0.14), in: Circle())

                        Text("Liste kilitli")
                            .font(Theme.Typography.screenTitle)
                            .foregroundColor(Theme.Palette.textPrimary)

                        Text(playlistName ?? "İçerik kaynağı")
                            .font(Theme.Typography.rowSubtitle)
                            .foregroundColor(Theme.Palette.textSecondary)

                        Text("Hızlı kurulumda belirlenen 4 haneli PIN'i gir.")
                            .font(Theme.Typography.rowSubtitle)
                            .foregroundColor(Theme.Palette.textTertiary)
                            .multilineTextAlignment(.center)

                        SecureField("4 haneli PIN", text: $pin)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .multilineTextAlignment(.center)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .padding(Theme.Spacing.lg)
                            .background(Theme.Palette.surfaceElevated)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: Theme.Radius.md,
                                    style: .continuous
                                )
                            )
                            .onChange(of: pin) { value in
                                pin = String(value.filter(\.isNumber).prefix(4))
                                errorMessage = nil
                            }

                        if let errorMessage {
                            InlineMessageView(text: errorMessage, kind: .error)
                        }

                        Button(action: unlock) {
                            HStack(spacing: Theme.Spacing.sm) {
                                if isChecking { ProgressView().tint(.white) }
                                Text("Listeyi aç")
                                Image(systemName: "arrow.right")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.md)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(brandColor)
                        .disabled(pin.count != 4 || isChecking)

                        Button("Başka kaynak kullan", action: onManageSources)
                            .foregroundColor(Theme.Palette.textSecondary)
                    }
                    .padding(Theme.Spacing.xl)
                    .background(Theme.Palette.surface.opacity(0.92))
                    .clipShape(
                        RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                            .strokeBorder(brandColor.opacity(0.18), lineWidth: 1)
                    }
                }
                .frame(maxWidth: 520)
                .padding(Theme.Spacing.xl)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var brand: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if let logoURL {
                RemoteImageView(url: logoURL, contentMode: .fit, targetWidth: 160) {
                    DefaultBrandLogoView()
                }
                .frame(width: 80, height: 80)
            } else {
                DefaultBrandLogoView()
                    .frame(width: 80, height: 80)
            }
            Text(brandName)
                .font(Theme.Typography.sectionTitle)
                .foregroundColor(Theme.Palette.textPrimary)
        }
    }

    private func unlock() {
        guard pin.count == 4 else { return }
        let enteredPIN = pin
        isChecking = true
        Task {
            let success = await onUnlock(enteredPIN)
            isChecking = false
            if !success {
                pin = ""
                errorMessage = "Liste PIN'i hatalı."
                Haptics.warning()
            } else {
                Haptics.success()
            }
        }
    }
}
