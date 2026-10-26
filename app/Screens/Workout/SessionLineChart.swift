import Charts
import FitnessCore
import SwiftUI

struct SessionPoint: Identifiable {
    /// ISO date, unique per session.
    let id: String
    let label: String
    let kg: Double
    let repsText: String
    var mark: SessionMark?
    /// Today's own PR (or the latest one): drawn larger so it is the first thing seen.
    var isPR: Bool { mark == .pr }
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
                if point.isPR && latest {
                    PointMark(x: .value("Session", point.id), y: .value("kg", point.kg))
                        .foregroundStyle(Theme.gold.opacity(0.22))
                        .symbolSize(420)
                }
                PointMark(x: .value("Session", point.id), y: .value("kg", point.kg))
                    .foregroundStyle(point.isPR ? Theme.gold : (point.mark == .notClean ? Theme.card : Theme.green))
                    .symbolSize(point.isPR ? (latest ? 130 : 90) : (point.mark == .notClean ? 70 : (latest ? 70 : 40)))
                    .annotation(position: .top, spacing: 3) {
                        Text(point.isPR ? "★ \(Format.number(point.kg))" : Format.number(point.kg))
                            .font(.system(size: point.isPR ? 12 : 11, weight: point.isPR ? .heavy : .bold))
                            .foregroundColor(point.isPR ? Theme.gold : (latest ? Theme.green : Theme.greenSoft))
                    }
                if point.mark == .notClean {
                    // Hollow dot: the green ring around the card-coloured centre.
                    PointMark(x: .value("Session", point.id), y: .value("kg", point.kg))
                        .foregroundStyle(Theme.green)
                        .symbol(.circle.strokeBorder(lineWidth: 2.2))
                        .symbolSize(90)
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
                            Text(point.repsText)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(point.isPR ? Theme.gold : Theme.greenSoft)
                        }
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityIdentifier("session-chart")
        .accessibilityLabel(points.contains { $0.isPR } ? "Chart with a PR session" : "Chart")
    }

    /// A little room above and below so the line shows its shape even when the weight barely changes.
    private var domain: ClosedRange<Double> {
        guard let low = points.map(\.kg).min(), let high = points.map(\.kg).max() else { return 0...1 }
        let padding = max((high - low) * 0.35, 1.5)
        return (low - padding)...(high + padding * 1.4)
    }
}
