import UIKit
import OctopusCore

/// One bounded snapshot after actual player dismissal. Values are UIKit state,
/// geometry, fixed animation property names, and classes; never accessibility
/// labels, content identifiers, URLs, or arbitrary animation keys.
@MainActor
enum PlayerDismissalDiagnostics {
    static func recordTabSelection(from: Int, to: Int) {
        Log.ui.notice("Player dismissal tabSelection from=\(from, privacy: .public) to=\(to, privacy: .public)")
    }

    static func schedule(window: UIWindow?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak window] in
            guard let window else { return }
            record(window: window)
        }
    }

    private static func record(window: UIWindow) {
        let root = window.rootViewController
        let rootInteraction = root?.viewIfLoaded.map { $0.isUserInteractionEnabled ? 1 : 0 } ?? -1
        let rootTransition = root?.transitionCoordinator != nil
        let rootModal = root?.presentedViewController != nil
        let ignoringEvents = UIApplication.shared.isIgnoringInteractionEvents
        let scene = window.windowScene
        let orientation = scene?.interfaceOrientation.rawValue ?? -1
        var locked = -1
        if #available(iOS 26.0, *), let scene {
            locked = scene.effectiveGeometry.isInterfaceOrientationLocked ? 1 : 0
        }
        let x = Double(window.bounds.minX), y = Double(window.bounds.minY)
        let width = Double(window.bounds.width), height = Double(window.bounds.height)
        Log.ui.notice("Player dismissal +2s windowUI=\(window.isUserInteractionEnabled, privacy: .public) rootUI=\(rootInteraction, privacy: .public) ignoresEvents=\(ignoringEvents, privacy: .public) transition=\(rootTransition, privacy: .public) modal=\(rootModal, privacy: .public) orientation=\(orientation, privacy: .public) locked=\(locked, privacy: .public) x=\(x, privacy: .public) y=\(y, privacy: .public) width=\(width, privacy: .public) height=\(height, privacy: .public)")
        if window.traitCollection.userInterfaceIdiom == .phone { recordPhoneHit(window: window) }
        recordAnimations(window: window)
    }

    private static func recordPhoneHit(window: UIWindow) {
        // Diagnostic candidate for the second tab in the five-tab phone layout.
        // Log its actual hit rectangle; do not assume this point is a tab button.
        let point = CGPoint(x: window.bounds.width / 3, y: window.bounds.height - 52)
        guard let hit = window.hitTest(point, with: nil) else {
            Log.ui.notice("Player dismissal +2s phoneHit=none")
            return
        }
        let rect = hit.convert(hit.bounds, to: window)
        var classes = [className(hit)], ancestor = hit.superview
        var selected = (hit as? UIControl).map { $0.isSelected ? 1 : 0 } ?? -1
        for _ in 0..<4 {
            guard let view = ancestor else { break }
            classes.append(className(view))
            if selected == -1, let control = view as? UIControl { selected = control.isSelected ? 1 : 0 }
            ancestor = view.superview
        }
        let chain = classes.joined(separator: "/")
        let x = Double(rect.minX), y = Double(rect.minY)
        let width = Double(rect.width), height = Double(rect.height)
        Log.ui.notice("Player dismissal +2s phoneHit=\(chain, privacy: .public) selected=\(selected, privacy: .public) x=\(x, privacy: .public) y=\(y, privacy: .public) width=\(width, privacy: .public) height=\(height, privacy: .public)")
    }

    private static func recordAnimations(window: UIWindow) {
        let knownKeys: Set<String> = [
            "position", "bounds", "bounds.origin", "bounds.size", "opacity", "transform",
            "transform.scale", "transform.rotation", "backgroundColor", "cornerRadius", "path"
        ]
        var queue: [UIView] = [window], index = 0
        var keyCount = 0, inspectedCount = 0, repeated = 0, maxDuration = 0.0
        var recognized: Set<String> = []
        while index < queue.count, index < 200 {
            let view = queue[index]
            index += 1
            let keys = view.layer.animationKeys() ?? []
            keyCount += keys.count
            for key in keys.prefix(8) {
                if knownKeys.contains(key) { recognized.insert(key) }
                guard let animation = view.layer.animation(forKey: key) else { continue }
                inspectedCount += 1
                if animation.repeatCount > 1 || animation.repeatDuration > 0 { repeated += 1 }
                maxDuration = max(maxDuration, animation.duration)
            }
            queue.append(contentsOf: view.subviews.prefix(max(0, 200 - queue.count)))
        }
        let keys = recognized.sorted().joined(separator: ",")
        Log.ui.notice("Player dismissal +2s viewLayers=\(index, privacy: .public) animationKeys=\(keyCount, privacy: .public) inspected=\(inspectedCount, privacy: .public) repeated=\(repeated, privacy: .public) maxDuration=\(maxDuration, privacy: .public) knownProperties=\(keys, privacy: .public)")
    }

    private static func className(_ view: UIView) -> String {
        String(NSStringFromClass(type(of: view)).prefix(120))
    }
}
