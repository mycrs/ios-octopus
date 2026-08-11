import SwiftUI
import OctopusDesignSystem

extension PlayerScreen {

    func handleGestureSkip(_ delta: TimeInterval) {
        Task { await controller.skip(by: delta) }
        showGestureNotice(
            PlayerGestureNotice(
                icon: delta < 0 ? "gobackward.10" : "goforward.10",
                text: AppLocalization.localized(
                    delta < 0 ? "10 saniye geri" : "10 saniye ileri",
                    locale: locale
                )
            )
        )
    }

    func handleGestureVolume(_ value: Float) {
        controller.setVolume(value)
        showGestureNotice(
            PlayerGestureNotice(
                icon: value == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                text: AppLocalization.localized(
                    "Ses %%%ld",
                    locale: locale,
                    Int(value * 100)
                )
            )
        )
    }

    func handleGestureBrightness(_ value: CGFloat) {
        showGestureNotice(
            PlayerGestureNotice(
                icon: "sun.max.fill",
                text: AppLocalization.localized(
                    "Parlaklık %%%ld",
                    locale: locale,
                    Int(value * 100)
                )
            )
        )
    }

    func showGestureNotice(_ notice: PlayerGestureNotice) {
        gestureNoticeTask?.cancel()
        gestureNotice = notice
        gestureNoticeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled else { return }
            gestureNotice = nil
        }
    }
}
