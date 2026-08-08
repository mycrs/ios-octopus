import SwiftUI

/// Ekran içi arama alanı.
///
/// SwiftUI'ın `.searchable` değiştiricisi aramayı **gezinme çubuğuna**
/// yerleştirir; referans uygulamada ise arama kutusu kategori şeridinin
/// altında, içeriğin bir parçası olarak duruyor. Sıralamayı kontrol
/// edebilmek için kendi alanımızı çiziyoruz.
public struct SearchField: View {

    @Binding private var text: String
    private let placeholder: String

    public init(text: Binding<String>, placeholder: String) {
        self._text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.Palette.textTertiary)

            TextField(placeholder, text: $text)
                .foregroundColor(Theme.Palette.textPrimary)
                // Kanal adları büyük harfle başlamak zorunda değil ve
                // otomatik düzeltme arama sonucunu bozuyor.
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Aramayı temizle")
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Palette.surface)
        .clipShape(Capsule())
    }
}
