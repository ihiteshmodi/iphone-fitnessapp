import Foundation

/// What the muscle editor is editing: a role (or none) per part. Pure, so every tap is testable without the screen.
public struct MuscleSelection: Equatable {
    public enum RegionState: Equatable {
        /// No part of the region is selected.
        case none
        /// Some parts are selected, or some only as secondary.
        case some
        /// Every part of the region is primary.
        case all
    }

    private var roles: [MusclePart: MuscleRole] = [:]

    public init(assignments: [MuscleAssignment] = []) {
        for assignment in assignments { roles[assignment.part] = assignment.role }
    }

    public var isEmpty: Bool { roles.isEmpty }

    /// In body order.
    public var assignments: [MuscleAssignment] {
        roles.map { MuscleAssignment(part: $0.key, role: $0.value) }.sorted { $0.part.order < $1.part.order }
    }

    public func role(of part: MusclePart) -> MuscleRole? { roles[part] }

    public mutating func setRole(_ role: MuscleRole?, for part: MusclePart) {
        roles[part] = role
    }

    /// None, then primary, then secondary, then none again.
    public mutating func cycle(_ part: MusclePart) {
        switch roles[part] {
        case nil: roles[part] = .primary
        case .primary?: roles[part] = .secondary
        case .secondary?: roles[part] = nil
        }
    }

    public mutating func selectEntire(_ region: MuscleRegion) {
        for part in region.parts { roles[part] = .primary }
    }

    public mutating func clear(_ region: MuscleRegion) {
        for part in region.parts { roles[part] = nil }
    }

    /// The region button: select the whole region, or clear it when it is already entirely selected.
    public mutating func toggleEntire(_ region: MuscleRegion) {
        if state(of: region) == .all { clear(region) } else { selectEntire(region) }
    }

    public func state(of region: MuscleRegion) -> RegionState {
        let parts = region.parts
        if parts.allSatisfy({ roles[$0] == .primary }) { return .all }
        return parts.contains { roles[$0] != nil } ? .some : .none
    }
}
