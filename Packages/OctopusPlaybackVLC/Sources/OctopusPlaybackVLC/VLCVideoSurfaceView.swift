import UIKit

/// VLC görüntü alanının boyutu değiştiğinde motoru haberdar eder.
///
/// `videoAspectRatio` doldurma modunda pencere oranına bağlıdır. iPhone
/// döndürüldüğünde eski oran korunursa video ya esner ya da siyah bant bırakır.
final class VLCVideoSurfaceView: UIView {

    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
