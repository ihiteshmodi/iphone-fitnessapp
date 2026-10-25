import Charts
import SwiftUI

struct RingView: View {
    let progress: Double
    var size: CGFloat = 44
    var lineWidth: CGFloat = 5
    var label: String? = nil
    var subLabel: String? = nil
    var color: Color = Theme.green

    var body: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let label {
                VStack(spacing: 1) {
                    Text(label)
                        .font(.system(size: size > 80 ? size * 0.22 : size * 0.26, weight: .bold))
                        .foregroundColor(Theme.text)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if let subLabel {
                        Text(subLabel).font(.system(size: size * 0.1)).foregroundColor(Theme.muted)
                    }
                }
                .padding(lineWidth + 2)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Tiny trend line used on workout cards. Green = rising, amber = flat, red = falling.
struct SparklineView: View {
    let values: [Double]
    var width: CGFloat = 120
    var height: CGFloat = 18

    private var tint: Color {
        guard let first = values.first, let last = values.last else { return Theme.muted }
        if values.max() == values.min() { return Theme.amber }
        return last < first ? Theme.red : Theme.green
    }

    var body: some View {
        if values.count < 2 {
            Capsule().fill(Theme.line).frame(width: width, height: 3)
        } else {
            let low = values.min() ?? 0, span = max((values.max() ?? 1) - low, 0.0001)
            Canvas { context, size in
                let points = values.enumerated().map { index, value in
                    CGPoint(x: 3 + CGFloat(index) * (size.width - 6) / CGFloat(values.count - 1),
                            y: size.height - 3 - CGFloat((value - low) / span) * (size.height - 6))
                }
                var path = Path()
                path.move(to: points[0])
                points.dropFirst().forEach { path.addLine(to: $0) }
                context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    context.fill(Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)), with: .color(tint))
                }
            }
            .frame(width: width, height: height)
        }
    }
}

struct ChartPoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    var series: String = "main"
    var caption: String? = nil
}

/// Green line chart with an optional dashed target line, used for sessions, weight, measurements and volume.
struct TrendChart: View {
    let points: [ChartPoint]
    var targetLine: Double? = nil
    var height: CGFloat = 150
    var seriesColors: [String: Color] = [:]

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Date", point.label), y: .value("Value", point.value), series: .value("Series", point.series))
                    .foregroundStyle(color(for: point.series))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", point.label), y: .value("Value", point.value))
                    .foregroundStyle(color(for: point.series))
                    .symbolSize(28)
                    .annotation(position: .top, spacing: 2) {
                        if let caption = point.caption {
                            Text(caption).font(.system(size: 9)).foregroundColor(color(for: point.series))
                        }
                    }
            }
            if let targetLine {
                RuleMark(y: .value("Target", targetLine))
                    .foregroundStyle(Theme.greenSoft)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel().foregroundStyle(Theme.muted)
            }
        }
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.muted) }
        }
        .frame(height: height)
    }

    private func color(for series: String) -> Color { seriesColors[series] ?? Theme.green }

    private var yDomain: ClosedRange<Double> {
        var values = points.map(\.value)
        if let targetLine { values.append(targetLine) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let padding = max((high - low) * 0.15, 0.5)
        return (low - padding)...(high + padding)
    }
}

struct SetChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Theme.text)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Theme.card2)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
