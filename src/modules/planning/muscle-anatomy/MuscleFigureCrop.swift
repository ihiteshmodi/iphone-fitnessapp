import CoreGraphics
import Foundation

/// A rectangle (in the 200 x 440 figure box) to zoom the figure to, for one side of the body.
public struct MuscleFrame: Equatable {
    public let view: BodyView
    public let rect: CGRect
}

/// Works out how the small "Muscles worked" card frames the body, so it shows only what matters.
public enum MuscleFigureCrop {
    /// Space kept around the muscles.
    public static let padding = 10.0
    /// Smallest frame side, so a small muscle still shows where on the body it is.
    public static let minimumSide = 90.0

    /// One frame per side of the body that holds a primary muscle (front first). With no primary muscle, every
    /// chosen muscle is framed instead. Secondary muscles are not framed; they show only where they fall inside.
    public static func frames(for muscles: [MuscleAssignment]) -> [MuscleFrame] {
        let primary = muscles.filter { $0.role == .primary }
        let framed = (primary.isEmpty ? muscles : primary).map(\.part)
        return BodyView.allCases.compactMap { view in
            frame(for: framed, view: view).map { MuscleFrame(view: view, rect: $0) }
        }
    }

    /// The frame around the given parts as drawn on one side, or nil when none of them is drawn there.
    public static func frame(for parts: [MusclePart], view: BodyView) -> CGRect? {
        let shapes = parts.flatMap { shapes(of: $0, view: view) }
        guard let bounds = bounds(of: shapes) else { return nil }

        let figureWidth = MuscleFigureData.width
        let figureHeight = MuscleFigureData.height
        let side = max(bounds.width + 2 * padding, bounds.height + 2 * padding, minimumSide)
        let width = min(side, figureWidth)
        let height = min(side, figureHeight)
        let x = min(max(bounds.midX - width / 2, 0), figureWidth - width)
        let y = min(max(bounds.midY - height / 2, 0), figureHeight - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The box around every coordinate in the path data (control points included, which is close enough for framing).
    public static func bounds(of paths: [String]) -> CGRect? {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for path in paths {
            let numbers = path.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
            var index = 0
            while index + 1 < numbers.count {
                minX = min(minX, numbers[index]); maxX = max(maxX, numbers[index])
                minY = min(minY, numbers[index + 1]); maxY = max(maxY, numbers[index + 1])
                index += 2
            }
        }
        guard minX.isFinite, minY.isFinite else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func shapes(of part: MusclePart, view: BodyView) -> [String] {
        (view == .front ? MuscleFigureData.front : MuscleFigureData.back)[part.rawValue] ?? []
    }
}
