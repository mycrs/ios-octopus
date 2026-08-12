import SwiftUI

/// Kategori değişiminde mevcut içeriği yok etmeden yeni kataloğun hazırlandığını gösterir.
public struct CatalogTransitionOverlay: View {
    @Environment(\.brandColor) private var brandColor

    public init() {}

    public var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ProgressView()
                .controlSize(.small)
                .tint(brandColor)
            Text("İçerikler hazırlanıyor")
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundColor(Theme.Palette.textPrimary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(minHeight: 38)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().stroke(brandColor.opacity(0.18), lineWidth: 1) }
        .shadow(color: Color.black.opacity(0.22), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
    }
}
