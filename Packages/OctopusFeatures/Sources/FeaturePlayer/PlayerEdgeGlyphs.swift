import SwiftUI
import UIKit

enum PlayerEdgeGlyph {
    case close
    case options
}

struct PlayerEdgeControlVisual: View {
    let glyph: PlayerEdgeGlyph

    var body: some View {
        Image(uiImage: PlayerEdgeControlImage.image(for: glyph))
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
    }
}

enum PlayerEdgeControlImage {
    static let size = CGSize(width: 44, height: 44)

    private static let closeImage = makeImage(for: .close)
    private static let optionsImage = makeImage(for: .options)

    static func image(for glyph: PlayerEdgeGlyph) -> UIImage {
        switch glyph {
        case .close: return closeImage
        case .options: return optionsImage
        }
    }

    private static func makeImage(for glyph: PlayerEdgeGlyph) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { rendererContext in
            let context = rendererContext.cgContext
            let circleRect = CGRect(origin: .zero, size: size)
                .insetBy(dx: 0.25, dy: 0.25)
            context.setFillColor(UIColor.black.withAlphaComponent(0.58).cgColor)
            context.fillEllipse(in: circleRect)
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.14).cgColor)
            context.setLineWidth(0.5)
            context.strokeEllipse(in: circleRect)

            switch glyph {
            case .close:
                drawClose(in: context)
            case .options:
                drawOptions(in: context)
            }
        }
        .withRenderingMode(.alwaysOriginal)
    }

    private static func drawClose(in context: CGContext) {
        let inset = size.width * 0.32
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(3.5)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: inset, y: inset))
        context.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
        context.move(to: CGPoint(x: size.width - inset, y: inset))
        context.addLine(to: CGPoint(x: inset, y: size.height - inset))
        context.strokePath()
    }

    private static func drawOptions(in context: CGContext) {
        let diameter = size.width * 0.10
        let y = size.height / 2 - diameter / 2
        let centers = [size.width * 0.30, size.width * 0.50, size.width * 0.70]
        context.setFillColor(UIColor.white.cgColor)
        for center in centers {
            context.fillEllipse(
                in: CGRect(
                    x: center - diameter / 2,
                    y: y,
                    width: diameter,
                    height: diameter
                )
            )
        }
    }
}
