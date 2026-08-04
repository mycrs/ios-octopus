import SwiftUI
import OctopusDomain

/// Yükleniyor durumu.
public struct LoadingStateView: View {

    private let message: String?

    public init(message: String? = nil) {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(Theme.Palette.accent)
            if let message {
                Text(message)
                    .font(Theme.Typography.rowSubtitle)
                    .foregroundColor(Theme.Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Hata durumu. `AppError`'ın sunum uzantılarını kullanır —
/// her ekranda hata metni yeniden yazılmaz.
public struct ErrorStateView: View {

    private let error: AppError
    private let onRetry: (() -> Void)?

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
                Text(error.userTitle)
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(Theme.Palette.textPrimary)

                Text(error.userMessage)
                    .font(Theme.Typography.rowSubtitle)
                    .foregroundColor(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let onRetry, let title = error.primaryActionTitle {
                Button(title, action: onRetry)
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
                Text(title)
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(Theme.Palette.textPrimary)

                if let message {
                    Text(message)
                        .font(Theme.Typography.rowSubtitle)
                        .foregroundColor(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
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
