import SwiftUI

/// Etiketli metin alanı.
///
/// IPTV adresleri elle yazılır ve tek harf hatası bağlantıyı bozar;
/// bu yüzden otomatik büyük harf ve otomatik düzeltme kapalıdır.
public struct FormFieldView: View {

    private let title: String
    private let placeholder: String
    private let icon: String?
    @Binding private var text: String
    private let isSecure: Bool
    private let contentType: UITextContentType?
    @State private var revealsSecureText = false
    @Environment(\.brandColor) private var brandColor
    @Environment(\.locale) private var locale

    public init(
        title: String,
        placeholder: String,
        text: Binding<String>,
        icon: String? = nil,
        isSecure: Bool = false,
        contentType: UITextContentType? = nil
    ) {
        self.title = title
        self.placeholder = placeholder
        self.icon = icon
        self._text = text
        self.isSecure = isSecure
        self.contentType = contentType
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(AppLocalization.localized(title, locale: locale))
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Palette.textSecondary)

            HStack(spacing: Theme.Spacing.md) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(brandColor)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                }

                Group {
                    if isSecure {
                        if revealsSecureText {
                            TextField(AppLocalization.localized(placeholder, locale: locale), text: $text)
                        } else {
                            SecureField(AppLocalization.localized(placeholder, locale: locale), text: $text)
                        }
                    } else {
                        TextField(AppLocalization.localized(placeholder, locale: locale), text: $text)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(contentType == .URL ? .URL : .default)
                .textContentType(contentType)
                .foregroundColor(Theme.Palette.textPrimary)

                if isSecure, !text.isEmpty {
                    Button {
                        revealsSecureText.toggle()
                    } label: {
                        Image(systemName: revealsSecureText ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.Palette.textSecondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(revealsSecureText ? "Parolayı gizle" : "Parolayı göster")
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: 52)
            .background(Theme.Palette.surfaceElevated.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(Theme.Palette.separator.opacity(0.9), lineWidth: 1)
            }
        }
    }
}

/// Form içi bilgi/hata şeridi.
public struct InlineMessageView: View {

    public enum Kind {
        case error
        case info

        var icon: String {
            switch self {
            case .error: return "exclamationmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    private let text: String
    private let kind: Kind
    @Environment(\.brandColor) private var brandColor
    @Environment(\.locale) private var locale

    public init(text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }

    private var presentationColor: Color {
        switch kind {
        case .error: return Theme.Palette.error
        case .info: return brandColor
        }
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(presentationColor.opacity(0.15))
                Image(systemName: kind.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(presentationColor)
            }
            .frame(width: 30, height: 30)

            Text(AppLocalization.localized(text, locale: locale))
                .font(Theme.Typography.rowSubtitle)
                .foregroundColor(Theme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Spacing.xs)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .background(presentationColor.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(presentationColor.opacity(0.22), lineWidth: 1)
        }
    }
}
