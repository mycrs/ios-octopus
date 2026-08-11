import SwiftUI
import OctopusDomain

/// Yükleniyor durumu.
public struct LoadingStateView: View {

    private let message: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @State private var isPulsing = false

    public init(message: String? = nil) {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Theme.Palette.accent.opacity(0.10))
                    .frame(width: 76, height: 76)
                    .scaleEffect(isPulsing && !reduceMotion ? 1.12 : 0.94)
                    .opacity(isPulsing && !reduceMotion ? 0.45 : 1)

                Circle()
                    .fill(Theme.Palette.surfaceElevated)
                    .frame(width: 58, height: 58)
                    .overlay {
                        Circle()
                            .stroke(Theme.Palette.accent.opacity(0.2), lineWidth: 1)
                    }

                ProgressView()
                    .tint(Theme.Palette.accent)
                    .scaleEffect(1.05)
            }

            VStack(spacing: Theme.Spacing.xs) {
                Text(AppLocalization.localized(message ?? "Yükleniyor", locale: locale))
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(Theme.Palette.textPrimary)

                Text("Birazdan hazır")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textTertiary)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppLocalization.localized(message ?? "Yükleniyor", locale: locale))
        .onAppear { isPulsing = true }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 1.15).repeatForever(autoreverses: true),
            value: isPulsing
        )
    }
}

/// Hata durumu. `AppError`'ın sunum uzantılarını kullanır —
/// her ekranda hata metni yeniden yazılmaz.
public struct ErrorStateView: View {

    private let error: AppError
    private let onRetry: (() -> Void)?
    @Environment(\.locale) private var locale

    public init(error: AppError, onRetry: (() -> Void)? = nil) {
        self.error = error
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: error.iconName)
                .font(.system(size: 44))
                .foregroundColor(Theme.Palette.textTertiary)

            VStack(spacing: Theme.Spacing.xs) {
                Text(AppLocalization.localized(error.userTitle, locale: locale))
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(Theme.Palette.textPrimary)

                Text(AppLocalization.localized(error.userMessage, locale: locale))
                    .font(Theme.Typography.rowSubtitle)
                    .foregroundColor(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let onRetry, let title = error.primaryActionTitle {
                Button(AppLocalization.localized(title, locale: locale), action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Palette.accent)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// İçerik yok durumu (hata değil — liste gerçekten boş).
public struct EmptyStateView: View {

    private let icon: String
    private let title: String
    private let message: String?
    private let actionTitle: String?
    private let action: (() -> Void)?
    @Environment(\.locale) private var locale

    public init(
        icon: String = "tray",
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(Theme.Palette.textTertiary)

            VStack(spacing: Theme.Spacing.xs) {
                Text(AppLocalization.localized(title, locale: locale))
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(Theme.Palette.textPrimary)

                if let message {
                    Text(AppLocalization.localized(message, locale: locale))
                        .font(Theme.Typography.rowSubtitle)
                        .foregroundColor(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            if let actionTitle, let action {
                Button(AppLocalization.localized(actionTitle, locale: locale), action: action)
                    .buttonStyle(.bordered)
                    .tint(Theme.Palette.accent)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Ekranların ortak yükleme/hata/boş/içerik durumu sarmalayıcısı.
///
/// Her ViewModel aynı dört durumu yaşar; her ekranda `if isLoading … else if error …`
/// yazmak yerine bu tip kullanılır.
public enum LoadableState<Value: Equatable>: Equatable {
    case idle
    case loading
    case loaded(Value)
    case failed(AppError)

    public var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    public var isLoading: Bool {
        self == .loading
    }
}
