import UIKit

/// Dokunsal geri bildirim.
///
/// Görsel dil Android sürümüyle aynı ama his iOS'a özgü olmalı — kilitli
/// tasarım kararı buydu (bkz. Docs/BRAIN.md § 1). Bir favoriye dokunmak
/// veya yanlış PIN girmek parmakta da karşılık bulmalı.
///
/// ⚠️ iOS 16 hedefi: SwiftUI'ın `.sensoryFeedback` değiştiricisi **iOS 17+**.
/// Bu yüzden UIKit üreteçleri kullanılıyor.
///
/// ⚠️ Üreteçler saklanıyor, her çağrıda yeniden kurulmuyor: `prepare()`
/// çağrısı olmadan ilk titreşim gözle görülür şekilde gecikiyor.
@MainActor
public enum Haptics {

    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)

    /// Seçim değişti — kategori sekmesi, sezon, açılış tercihi.
    public static func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    /// İşlem başarılı — favoriye eklendi, kilit kuruldu, senkronizasyon bitti.
    public static func success() {
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
    }

    /// İşlem reddedildi — yanlış PIN, geçersiz kaynak.
    ///
    /// `.error` değil `.warning`: `.error` kalıbı iOS'ta "bir şey bozuldu"
    /// hissi veriyor, oysa yanlış PIN beklenen bir sonuç.
    public static func warning() {
        notificationGenerator.notificationOccurred(.warning)
        notificationGenerator.prepare()
    }

    /// Hafif dokunuş — favoriden çıkarma gibi geri alınabilir eylemler.
    public static func light() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
    }
}
