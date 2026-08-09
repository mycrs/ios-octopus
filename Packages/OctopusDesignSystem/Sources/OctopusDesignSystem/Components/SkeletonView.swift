import SwiftUI

/// Yükleme sırasında içeriğin **şeklini** gösteren yer tutucu.
///
/// ## Neden spinner değil?
/// Ortada dönen bir çark iki şeyi birden kaybettiriyordu: kullanıcı ne
/// geleceğini bilmiyor (kaç kart? liste mi ızgara mı?) ve ekran her
/// yüklemede tamamen boşalıp doluyordu — sayfalar arası geçiş "zıplama"
/// gibi hissettiriyordu. İskelet, gelecek düzenin aynısını çizer; içerik
/// gelince yalnızca **içi dolar**, yerleşim oynamaz.
///
/// ⚠️ "Hareketi azalt" (Reduce Motion) açıkken parıltı animasyonu
/// çalışmaz — sürekli hareket eden bir yüzey o ayarın tam olarak
/// engellemek istediği şey.
public struct SkeletonBox: View {

    private let cornerRadius: CGFloat
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(cornerRadius: CGFloat = Theme.Radius.md) {
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.Palette.surface)
            .overlay { shimmer }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 2
                }
            }
    }

    /// Soldan sağa geçen açık bant.
    @ViewBuilder
    private var shimmer: some View {
        if reduceMotion {
            EmptyView()
        } else {
            GeometryReader { geometry in
                LinearGradient(
                    colors: [
                        .clear,
                        Theme.Palette.surfaceElevated.opacity(0.9),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geometry.size.width * 0.6)
                .offset(x: phase * geometry.size.width)
            }
        }
    }
}

/// Afiş ızgarası iskeleti — Filmler ve Diziler.
public struct PosterGridSkeleton: View {

    private let count: Int
    private let columns: [GridItem]

    /// - Parameter count: Kaç yer tutucu çizilsin. Varsayılan, ilk ekranı
    ///   dolduracak kadar; daha fazlası boşuna çizim.
    public init(count: Int = 9) {
        self.count = count
        self.columns = Array(
            repeating: GridItem(.flexible(), spacing: Theme.Spacing.md),
            count: 3
        )
    }

    public var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SkeletonBox()
                        // 2:3 afiş oranı — gerçek kartla birebir aynı,
                        // içerik gelince ızgara kaymaz.
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)

                    SkeletonBox(cornerRadius: Theme.Radius.sm)
                        .frame(height: 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .accessibilityElement()
        .accessibilityLabel("İçerikler yükleniyor")
    }
}

/// Satır listesi iskeleti — kanal listesi.
public struct RowListSkeleton: View {

    private let count: Int

    public init(count: Int = 8) {
        self.count = count
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: Theme.Spacing.md) {
                    SkeletonBox()
                        .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        SkeletonBox(cornerRadius: Theme.Radius.sm)
                            .frame(height: 14)
                            .frame(maxWidth: 180, alignment: .leading)

                        SkeletonBox(cornerRadius: Theme.Radius.sm)
                            .frame(height: 11)
                            .frame(maxWidth: 120, alignment: .leading)
                    }

                    Spacer(minLength: 0)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Palette.surface.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .accessibilityElement()
        .accessibilityLabel("Kanallar yükleniyor")
    }
}

/// Ana sayfa iskeleti: hero + iki yatay raf.
public struct ShelvesSkeleton: View {

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            // Hero — kenara yapışık, gerçek kartla aynı yükseklikte.
            SkeletonBox(cornerRadius: 0)
                .frame(height: 260)

            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    SkeletonBox(cornerRadius: Theme.Radius.sm)
                        .frame(width: 160, height: 16)
                        .padding(.horizontal, Theme.Spacing.md)

                    HStack(spacing: Theme.Spacing.md) {
                        ForEach(0..<3, id: \.self) { _ in
                            SkeletonBox()
                                .frame(width: 104, height: 156)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement()
        .accessibilityLabel("Ana sayfa yükleniyor")
    }
}
