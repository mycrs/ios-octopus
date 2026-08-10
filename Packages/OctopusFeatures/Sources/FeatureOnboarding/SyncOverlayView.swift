import SwiftUI
import OctopusDomain
import OctopusDesignSystem

/// Doğrulama ve ilk senkronizasyon sırasında gösterilen katman.
///
/// Referans dersi: kullanıcı kanal açılmasını beklerken hiçbir geri bildirim
/// göremediğinde uygulamanın donduğunu sanıyor. Burada her aşama adıyla
/// bildirilir; ilerleme oranı bilinmiyorsa belirsiz gösterge kullanılır.
struct SyncOverlayView: View {

    let step: AddPlaylistViewModel.Step
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.66).ignoresSafeArea()
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .opacity(0.16)

            VStack(spacing: Theme.Spacing.xl) {
                indicator

                VStack(spacing: Theme.Spacing.sm) {
                    Text(eyebrow)
                        .font(Theme.Typography.badge)
                        .tracking(1.2)
                        .foregroundColor(Theme.Palette.accent)

                    Text(title)
                        .font(Theme.Typography.sectionTitle)
                        .foregroundColor(Theme.Palette.textPrimary)
                        .multilineTextAlignment(.center)

                    if let detail {
                        Text(detail)
                            .font(Theme.Typography.rowSubtitle)
                            .foregroundColor(Theme.Palette.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                progressTrack
            }
            .padding(Theme.Spacing.xxl)
            .frame(maxWidth: 380)
            .background(.regularMaterial)
            .environment(\.colorScheme, .dark)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.42), radius: 32, y: 18)
            .padding(Theme.Spacing.xl)
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail ?? "")")
        .onAppear { isPulsing = true }
    }

    private var indicator: some View {
        ZStack {
            Circle()
                .fill(Theme.Palette.accent.opacity(0.10))
                .frame(width: 104, height: 104)
                .scaleEffect(isPulsing && !reduceMotion ? 1.10 : 0.96)
                .opacity(isPulsing && !reduceMotion ? 0.42 : 1)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                    value: isPulsing
                )

            Circle()
                .stroke(Theme.Palette.separator, lineWidth: 6)
                .frame(width: 82, height: 82)

            if let fraction {
                Circle()
                    .trim(from: 0, to: max(fraction, 0.04))
                    .stroke(
                        Theme.Palette.accent,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 82, height: 82)
                    .animation(.easeInOut(duration: 0.35), value: fraction)

                Text("\(Int(fraction * 100))%")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.Palette.textPrimary)
                    .monospacedDigit()
            } else {
                ProgressView()
                    .tint(Theme.Palette.accent)
                    .scaleEffect(1.15)
            }
        }
    }

    private var progressTrack: some View {
        VStack(spacing: Theme.Spacing.sm) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.separator)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Theme.Palette.accent, Theme.Palette.success],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * trackFraction)
                }
            }
            .frame(height: 5)

            HStack {
                Text("BAĞLAN")
                Spacer()
                Text("AKTAR")
                Spacer()
                Text("HAZIR")
            }
            .font(Theme.Typography.badge)
            .foregroundColor(Theme.Palette.textTertiary)
        }
    }

    // MARK: - Aşama metinleri

    private var title: String {
        switch step {
        case .searchingServer(let index, let total):
            return "Sunucu aranıyor (\(index)/\(total))"
        case .validating:
            return "Bağlantı sınanıyor"
        case .syncing(let stage):
            return stage.title
        case .form, .done:
            return ""
        }
    }

    private var eyebrow: String {
        switch step {
        case .searchingServer, .validating: return "BAĞLANTI KURULUYOR"
        case .syncing: return "İÇERİKLER HAZIRLANIYOR"
        case .form, .done: return "KURULUM"
        }
    }

    private var detail: String? {
        switch step {
        case .searchingServer:
            return "Bayinin sunucuları sırayla deneniyor. Hesabının çalıştığı "
                + "sunucu bulununca kurulum kendiliğinden sürecek."
        case .validating:
            return "Sunucuya erişiliyor ve hesap bilgilerin doğrulanıyor."
        case .syncing:
            return "İlk kurulum biraz sürebilir. Büyük listelerde bu adım uzun olabilir."
        case .form, .done:
            return nil
        }
    }

    private var fraction: Double? {
        guard case .syncing(let stage) = step else { return nil }
        return stage.fraction
    }

    private var trackFraction: Double {
        switch step {
        case .searchingServer(let index, let total):
            guard total > 0 else { return 0.10 }
            return min(0.25, 0.08 + (Double(index) / Double(total)) * 0.17)
        case .validating: return 0.28
        case .syncing: return 0.28 + (fraction ?? 0.08) * 0.68
        case .form: return 0
        case .done: return 1
        }
    }
}

private extension SyncStage {
    var title: String {
        switch self {
        case .idle: return "Hazırlanıyor"
        case .authenticating: return "Hesap doğrulanıyor"
        case .fetchingCategories: return "Kategoriler alınıyor"
        case .fetchingChannels: return "Kanallar alınıyor"
        case .fetchingMovies: return "Filmler alınıyor"
        case .fetchingSeries: return "Diziler alınıyor"
        case .fetchingEPG: return "Yayın akışı alınıyor"
        case .persisting: return "Cihaza kaydediliyor"
        case .finished: return "Tamamlandı"
        case .failed: return "Bir sorun oluştu"
        }
    }
}
