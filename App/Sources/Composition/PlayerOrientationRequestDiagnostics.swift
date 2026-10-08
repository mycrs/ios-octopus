import UIKit

/// Convert only UIKit's known English orientation denial into enum bits.
/// Never log the description, controller identity, or arbitrary error data.
enum PlayerOrientationRequestDiagnostics {
    static func deniedMask(in description: String) -> UIInterfaceOrientationMask? {
        let prefix = "None of the requested orientations are supported by the view controller. Requested: "
        guard description.hasPrefix(prefix),
              let separator = description.range(of: "; Supported: ") else { return nil }
        var names = String(description[separator.upperBound...])
        if names.hasSuffix(".") { names.removeLast() }
        let orientations: [String: UIInterfaceOrientationMask] = [
            "portrait": .portrait, "portraitUpsideDown": .portraitUpsideDown,
            "landscapeLeft": .landscapeLeft, "landscapeRight": .landscapeRight
        ]
        let tokens = names.components(separatedBy: ", ")
        guard (1...4).contains(tokens.count), Set(tokens).count == tokens.count else { return nil }
        var mask: UIInterfaceOrientationMask = []
        for token in tokens {
            guard let orientation = orientations[token] else { return nil }
            mask.formUnion(orientation)
        }
        return mask
    }
}
