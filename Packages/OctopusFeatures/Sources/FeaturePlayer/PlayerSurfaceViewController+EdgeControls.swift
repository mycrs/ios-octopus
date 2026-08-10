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
            optionsBackground.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    func refreshOverlayOrder() {
        view.bringSubviewToFront(overlayHost.view)
        edgeViews.forEach { view.bringSubviewToFront($0) }
    }
}
