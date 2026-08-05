import SwiftUI

/// Etiketli metin alanı.
///
/// IPTV adresleri elle yazılır ve tek harf hatası bağlantıyı bozar;
/// bu yüzden otomatik büyük harf ve otomatik düzeltme kapalıdır.
public struct FormFieldView: View {

    private let title: String
    private let placeholder: String
    @Binding private var text: String
    private let isSecure: Bool
    private let contentType: UITextContentType?

    public init(
        title: String,
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool = false,
        contentType: UITextContentType? = nil
    ) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.isSecure = isSecure
        self.contentType = contentType
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Palette.textSecondary)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(contentType == .URL ? .URL : .default)
            .textContentType(contentType)
            .foregroundColor(Theme.Palette.textPrimary)
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
    }
}

/// Form içi bilgi/hata şeridi.
public struct InlineMessageView: View {

    public enum Kind {
        case error
        case info

        var color: Color {
            switch self {
            case .error: return Theme.Palette.error
            case .info: return Theme.Palette.accent
            }
        }

        var icon: String {
            switch self {
            case .error: return "exclamationmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    private let text: String
    private let kind: Kind

    public init(text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: kind.icon)
                .foregroundColor(kind.color)
            Text(text)
                .font(Theme.Typography.rowSubtitle)
                .foregroundColor(Theme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .background(kind.color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}
