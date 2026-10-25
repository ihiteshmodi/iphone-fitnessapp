import Foundation

/// Which side of the body a drawing shows.
public enum BodyView: String, CaseIterable, Hashable {
    case front
    case back
}

/// A group of muscle parts the editor can select in one tap ("the entire upper back").
public enum MuscleRegion: String, CaseIterable, Identifiable, Hashable {
    case chest, shoulders, upperBack, lowerBack, biceps, triceps, forearms, core, quads, hamstrings, glutes, hips, calves, shins

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .shoulders: return "Shoulders"
        case .upperBack: return "Upper back"
        case .lowerBack: return "Lower back"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .core: return "Core"
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .hips: return "Hips"
        case .calves: return "Calves"
        case .shins: return "Shins"
        }
    }

    public var parts: [MusclePart] { MusclePart.allCases.filter { $0.region == self } }
}

/// One drawn muscle. The raw value is the key stored in the database and used by the figure data, so never rename one.
/// Declaration order is body order from the top, and is the order lists are shown in.
public enum MusclePart: String, CaseIterable, Identifiable, Hashable {
    case chestUpper = "chest_upper"
    case chestMid = "chest_mid"
    case chestLower = "chest_lower"
    case deltFront = "delt_front"
    case deltSide = "delt_side"
    case deltRear = "delt_rear"
    case trapsUpper = "traps_upper"
    case trapsMid = "traps_mid"
    case trapsLower = "traps_lower"
    case lats
    case rhomboids
    case teres
    case erectors
    case biceps
    case brachialis
    case tricepsLong = "triceps_long"
    case tricepsLateral = "triceps_lateral"
    case forearmFlexors = "forearm_flexors"
    case forearmExtensors = "forearm_extensors"
    case abs
    case obliques
    case serratus
    case quadRectus = "quad_rectus"
    case quadOuter = "quad_outer"
    case quadInner = "quad_inner"
    case hamOuter = "ham_outer"
    case hamInner = "ham_inner"
    case gluteMax = "glute_max"
    case abductors
    case adductors
    case gastrocnemius
    case soleus
    case tibialis

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chestUpper: return "Upper chest"
        case .chestMid: return "Mid chest"
        case .chestLower: return "Lower chest"
        case .deltFront: return "Front delts"
        case .deltSide: return "Side delts"
        case .deltRear: return "Rear delts"
        case .trapsUpper: return "Upper traps"
        case .trapsMid: return "Mid traps"
        case .trapsLower: return "Lower traps"
        case .lats: return "Lats"
        case .rhomboids: return "Rhomboids"
        case .teres: return "Teres and rotator cuff"
        case .erectors: return "Spinal erectors"
        case .biceps: return "Biceps"
        case .brachialis: return "Brachialis"
        case .tricepsLong: return "Triceps long head"
        case .tricepsLateral: return "Triceps lateral head"
        case .forearmFlexors: return "Forearm flexors"
        case .forearmExtensors: return "Forearm extensors"
        case .abs: return "Abs"
        case .obliques: return "Obliques"
        case .serratus: return "Serratus"
        case .quadRectus: return "Rectus femoris"
        case .quadOuter: return "Outer quad"
        case .quadInner: return "Inner quad"
        case .hamOuter: return "Outer hamstring"
        case .hamInner: return "Inner hamstring"
        case .gluteMax: return "Glute max"
        case .abductors: return "Hip abductors"
        case .adductors: return "Hip adductors"
        case .gastrocnemius: return "Gastrocnemius"
        case .soleus: return "Soleus"
        case .tibialis: return "Tibialis"
        }
    }

    public var region: MuscleRegion {
        switch self {
        case .chestUpper, .chestMid, .chestLower: return .chest
        case .deltFront, .deltSide, .deltRear: return .shoulders
        case .trapsUpper, .trapsMid, .trapsLower, .lats, .rhomboids, .teres: return .upperBack
        case .erectors: return .lowerBack
        case .biceps, .brachialis: return .biceps
        case .tricepsLong, .tricepsLateral: return .triceps
        case .forearmFlexors, .forearmExtensors: return .forearms
        case .abs, .obliques, .serratus: return .core
        case .quadRectus, .quadOuter, .quadInner: return .quads
        case .hamOuter, .hamInner: return .hamstrings
        case .gluteMax: return .glutes
        case .abductors, .adductors: return .hips
        case .gastrocnemius, .soleus: return .calves
        case .tibialis: return .shins
        }
    }

    /// The sides of the body where this muscle is drawn. A test keeps this in step with the figure data.
    public var views: Set<BodyView> {
        switch self {
        case .deltSide, .trapsUpper, .abductors, .gastrocnemius:
            return [.front, .back]
        case .deltRear, .trapsMid, .trapsLower, .lats, .rhomboids, .teres, .erectors, .tricepsLong, .tricepsLateral,
             .forearmExtensors, .gluteMax, .hamOuter, .hamInner, .soleus:
            return [.back]
        default:
            return [.front]
        }
    }

    /// Position in body order, used to keep lists stable.
    public var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

public enum MuscleRole: String, Hashable {
    case primary
    case secondary
}

public struct MuscleAssignment: Hashable {
    public let part: MusclePart
    public let role: MuscleRole

    public init(part: MusclePart, role: MuscleRole) {
        self.part = part
        self.role = role
    }
}

/// The muscles an exercise trains, either worked out automatically or chosen by the user.
public struct ExerciseMuscles: Equatable {
    /// In body order, one entry per part.
    public let assignments: [MuscleAssignment]
    /// True when the user chose them; false when they come from the name and group rules.
    public let isCustom: Bool

    public init(assignments: [MuscleAssignment], isCustom: Bool) {
        self.assignments = MuscleSelection(assignments: assignments).assignments
        self.isCustom = isCustom
    }

    public var primary: [MusclePart] { assignments.filter { $0.role == .primary }.map(\.part) }
    public var secondary: [MusclePart] { assignments.filter { $0.role == .secondary }.map(\.part) }

    public func role(of part: MusclePart) -> MuscleRole? {
        assignments.first { $0.part == part }?.role
    }
}
