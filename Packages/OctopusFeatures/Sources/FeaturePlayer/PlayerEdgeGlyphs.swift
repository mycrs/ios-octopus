import SwiftUI

enum PlayerEdgeGlyph {
    case close
    case options
}

struct PlayerCloseGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.32
        var path = Path()
        path.move(to: CGPoint(x: inset, y: inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        path.move(to: CGPoint(x: rect.maxX - inset, y: inset))
        path.addLine(to: CGPoint(x: inset, y: rect.maxY - inset))
        return path
    }
}

struct PlayerOptionsGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let diameter = rect.width * 0.10
        let y = rect.midY - diameter / 2
        let centers = [rect.width * 0.30, rect.midX, rect.width * 0.70]
        var path = Path()

        for center in centers {
            path.addEllipse(
                in: CGRect(
                    x: center - diameter / 2,
                    y: y,
                    width: diameter,
                    height: diameter
                )
            )
        }
        return path
    }
}
