import Charts
import SwiftUI

struct SessionPoint: Identifiable {
    /// ISO date, unique per session.
    let id: String
    let label: String
    let kg: Double
    let repsText: String
}

/// Best set per session: weight as a line (the kg above each point), the date and the reps under each point.
struct SessionLineChart: View {
    let points: [SessionPoint]
    var height: CGFloat = 150

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                let latest = index == points.count - 1
                AreaMark(x: .value("Session", point.id), yStart: .value("Floor", domain.lowerBound), yEnd: .value("kg", point.kg))
                    .foregroundStyle(Theme.green.opacity(0.10))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Session", point.id), y: .value("kg", point.kg))
                    .foregroundStyle(Theme.green)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Session", point.id), y: .value("kg", point.kg))
                    .foregroundStyle(Theme.green)
                    .symbolSize(latest ? 70 : 40)
                    .annotation(position: .top, spacing: 3) {
                        Text(Format.number(point.kg))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(latest ? Theme.green : Theme.greenSoft)
                    }
            }
        }
        .chartYScale(domain: domain)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: points.map(\.id)) { value in
                AxisValueLabel(centered: true) {
                    if let id = value.as(String.self), let point = points.first(where: { $0.id == id }) {
                        VStack(spacing: 2) {
                            Text(point.label).font(.system(size: 10)).foregroundColor(Theme.muted)
                            Text(point.repsText).font(.system(size: 11, weight: .bold)).foregroundColor(Theme.greenSoft)
                        }
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityIdentifier("session-chart")
    }

    /// A little room above and below so the line shows its shape even when the weight barely changes.
    private var domain: ClosedRange<Double> {
        guard let low = points.map(\.kg).min(), let high = points.map(\.kg).max() else { return 0...1 }
        let padding = max((high - low) * 0.35, 1.5)
        return (low - padding)...(high + padding * 1.4)
    }
}
