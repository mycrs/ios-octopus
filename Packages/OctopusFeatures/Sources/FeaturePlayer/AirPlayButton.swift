import SwiftUI
import AVKit

/// Sistem AirPlay seçicisi.
///
/// ⚠️ Kendi düğmemizi çizip liste açamayız: cihaz seçimi Apple'ın
/// denetimindedir ve yalnızca `AVRoutePickerView` üzerinden sunulabilir.
/// Bu yüzden görünüm sarmalanıyor, taklit edilmiyor.
///
/// Düğme yalnızca motor AirPlay destekliyorsa gösterilir
/// (bkz. `PlaybackEngine.supportsAirPlay`) — VLC'de video karşıya
/// gitmediği için düğme çalışmayan bir vaat olurdu.
struct AirPlayButton: UIViewRepresentable {

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        // Bir cihaza bağlıyken vurgulanır; koyu arka planda görünsün diye
        // sistem varsayılanı yerine markanın vurgu rengi kullanılmıyor —
        // Apple bu düğmenin tanıdık kalmasını bekliyor.
        picker.activeTintColor = .white
        picker.prioritizesVideoDevices = true
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        // Durum sistemin elinde; güncellenecek bir şey yok.
    }
}
