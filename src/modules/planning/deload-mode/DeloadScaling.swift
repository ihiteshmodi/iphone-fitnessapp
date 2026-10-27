import Foundation

/// Deload only changes what is displayed; the stored plan keeps its real numbers.
public struct DeloadScaling: Equatable {
    public let settings: DeloadSettings

    public init(_ settings: DeloadSettings) { self.settings = settings }

    public var isActive: Bool { settings.enabled }

    public func workingWeight(heaviest: Double) -> Double {
        isActive ? heaviest * settings.weightMultiplier : heaviest
    }

    public func minReps(planned: Int) -> Double {
        isActive ? Double(planned) * settings.repsMultiplier : Double(planned)
    }

    /// The top of the rep range is lowered by the same multiplier as the bottom, so 8 to 16 becomes 6 to 12.
    public func maxReps(planned: Int) -> Double {
        isActive ? Double(planned) * settings.repsMultiplier : Double(planned)
    }
}
