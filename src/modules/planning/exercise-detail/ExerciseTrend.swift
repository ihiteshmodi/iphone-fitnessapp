import Foundation

public struct ExerciseTrend: Equatable {
    public enum Status: String, Equatable {
        case improving = "Improving"
        case flat = "Flat"
        case declining = "Declining"
        case notEnoughData = "Not enough data"
    }

    public let status: Status
    /// Newest estimate versus the mean of the earlier ones in the window; nil without enough data.
    public let percentChange: Double?

    public var label: String { status.rawValue }

    public static let windowSize = 5
    public static let flatBand = 2.0

    /// `estimates` are one-rep-max estimates per session, oldest first.
    public static func classify(_ estimates: [Double]) -> ExerciseTrend {
        let window = Array(estimates.suffix(windowSize))
        guard window.count >= 2, let newest = window.last else { return ExerciseTrend(status: .notEnoughData, percentChange: nil) }
        let earlier = window.dropLast()
        let baseline = earlier.reduce(0, +) / Double(earlier.count)
        guard baseline > 0 else { return ExerciseTrend(status: .flat, percentChange: nil) }

        let change = (newest - baseline) / baseline * 100
        let status: Status = change > flatBand ? .improving : (change < -flatBand ? .declining : .flat)
        return ExerciseTrend(status: status, percentChange: pyRound(change, 1))
    }
}
