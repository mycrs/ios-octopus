import UIKit
import OctopusDesignSystem

extension PlayerSurfaceViewController {

    func installEdgeGlyphs() {
        edgeViews.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.isHidden = !showsEdgeGlyphs
            view.addSubview($0)
        }

        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            closeBackground.leadingAnchor.constraint(
                equalTo: safeArea.leadingAnchor,
                constant: Theme.Spacing.md
            ),
            closeBackground.topAnchor.constraint(
                equalTo: safeArea.topAnchor,
                constant: Theme.Spacing.md
            ),
            closeBackground.widthAnchor.constraint(equalToConstant: 44),
            closeBackground.heightAnchor.constraint(equalToConstant: 44),
            optionsBackground.trailingAnchor.constraint(
                equalTo: safeArea.trailingAnchor,
                constant: -Theme.Spacing.md
            ),
            optionsBackground.topAnchor.constraint(
                equalTo: safeArea.topAnchor,
                constant: Theme.Spacing.md
            ),
            optionsBackground.widthAnchor.constraint(equalToConstant: 44),
            optionsBackground.heightAnchor.constraint(equalToConstant: 44),
            closeForwardMark.centerXAnchor.constraint(
                equalTo: closeBackground.centerXAnchor
            ),
            closeForwardMark.centerYAnchor.constraint(
                equalTo: closeBackground.centerYAnchor
            ),
            closeForwardMark.widthAnchor.constraint(equalToConstant: 19),
            closeForwardMark.heightAnchor.constraint(equalToConstant: 3),
            closeBackwardMark.centerXAnchor.constraint(
                equalTo: closeBackground.centerXAnchor
            ),
            closeBackwardMark.centerYAnchor.constraint(
                equalTo: closeBackground.centerYAnchor
            ),
            closeBackwardMark.widthAnchor.constraint(equalToConstant: 19),
            closeBackwardMark.heightAnchor.constraint(equalToConstant: 3),
            optionsLeftMark.centerXAnchor.constraint(
                equalTo: optionsBackground.centerXAnchor,
                constant: -8
            ),
            optionsCenterMark.centerXAnchor.constraint(
                equalTo: optionsBackground.centerXAnchor
            ),
            optionsRightMark.centerXAnchor.constraint(
                equalTo: optionsBackground.centerXAnchor,
                constant: 8
            ),
            optionsLeftMark.centerYAnchor.constraint(
                equalTo: optionsBackground.centerYAnchor
            ),
            optionsCenterMark.centerYAnchor.constraint(
                equalTo: optionsBackground.centerYAnchor
            ),
            optionsRightMark.centerYAnchor.constraint(
                equalTo: optionsBackground.centerYAnchor
            ),
            optionsLeftMark.widthAnchor.constraint(equalToConstant: 4),
            optionsLeftMark.heightAnchor.constraint(equalToConstant: 4),
            optionsCenterMark.widthAnchor.constraint(equalToConstant: 4),
            optionsCenterMark.heightAnchor.constraint(equalToConstant: 4),
            optionsRightMark.widthAnchor.constraint(equalToConstant: 4),
            optionsRightMark.heightAnchor.constraint(equalToConstant: 4)
        ])
    }

    func refreshOverlayOrder() {
        view.bringSubviewToFront(overlayHost.view)
        edgeViews.forEach { view.bringSubviewToFront($0) }
    }
}
