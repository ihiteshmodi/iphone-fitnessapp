import FitnessCore
import SwiftUI

/// Turns the figure's SVG path data (absolute M, C and Z only) into SwiftUI paths, once.
enum MuscleFigurePaths {
    static let base: [Path] = MuscleFigureData.base.map(path(from:))
    static let front: [String: [Path]] = MuscleFigureData.front.mapValues { $0.map(path(from:)) }
    static let back: [String: [Path]] = MuscleFigureData.back.mapValues { $0.map(path(from:)) }

    static func parts(in view: BodyView) -> [String: [Path]] { view == .front ? front : back }

    static func path(from data: String) -> Path {
        var path = Path()
        let tokens = data.split(separator: " ")
        var index = 0
        func number() -> CGFloat {
            defer { index += 1 }
            return index < tokens.count ? CGFloat(Double(tokens[index]) ?? 0) : 0
        }
        while index < tokens.count {
            let command = tokens[index]
            index += 1
            switch command {
            case "M":
                path.move(to: CGPoint(x: number(), y: number()))
            case "C":
                let control1 = CGPoint(x: number(), y: number())
                let control2 = CGPoint(x: number(), y: number())
                path.addCurve(to: CGPoint(x: number(), y: number()), control1: control1, control2: control2)
            case "Z":
                path.closeSubpath()
            default:
                break
            }
        }
        return path
    }
}

/// One side of the body with the given muscles highlighted. `frame` zooms to part of the figure (nil = the whole body).
struct MuscleFigureView: View {
    let view: BodyView
    let assignments: [MuscleAssignment]
    var frame: CGRect? = nil

    private static let silhouette = Color(hex: 0x131815)
    private static let silhouetteLine = Color(hex: 0x232A26)
    private static let idle = Color(hex: 0x1D2420)
    private static let idleLine = Color(hex: 0x2B352F)

    var body: some View {
        Canvas { context, size in
            let box = frame ?? CGRect(x: 0, y: 0, width: MuscleFigureData.width, height: MuscleFigureData.height)
            let scale = min(size.width / box.width, size.height / box.height)
            let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                              tx: (size.width - box.width * scale) / 2 - box.minX * scale,
                                              ty: (size.height - box.height * scale) / 2 - box.minY * scale)
            let hairline = max(0.5, 0.7 * scale)

            for shape in MuscleFigurePaths.base {
                let drawn = shape.applying(transform)
                context.fill(drawn, with: .color(Self.silhouette))
                context.stroke(drawn, with: .color(Self.silhouetteLine), lineWidth: hairline)
            }

            let roles = Dictionary(assignments.map { ($0.part, $0.role) }, uniquingKeysWith: { _, last in last })
            let shapes = MuscleFigurePaths.parts(in: view)
            for part in MusclePart.allCases {
                guard let paths = shapes[part.rawValue] else { continue }
                let fill: Color, line: Color
                switch roles[part] {
                case .primary?: fill = Theme.green; line = Theme.green
                case .secondary?: fill = Theme.green.opacity(0.42); line = Theme.green.opacity(0.42)
                case nil: fill = Self.idle; line = Self.idleLine
                }
                for shape in paths {
                    let drawn = shape.applying(transform)
                    context.fill(drawn, with: .color(fill))
                    context.stroke(drawn, with: .color(line), lineWidth: hairline)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
