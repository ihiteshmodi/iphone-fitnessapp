import Foundation

/// What to put in the water for a long, sweaty activity (a hike), from the vault's numbers. The daily workout mix is not
/// touched. Salt and potassium chloride shares are chemistry, not the vault.
public enum SweatyActivity {
    public enum Sweat: String, CaseIterable { case light, heavy }

    public struct Plan: Equatable {
        public let sodiumMg: ClosedRange<Double>
        public let saltGrams: ClosedRange<Double>
        public let potassiumMg: ClosedRange<Double>
        public let potassiumChlorideGrams: ClosedRange<Double>
        public let sipMl: ClosedRange<Double>
        public let sipEveryMinutes: ClosedRange<Double>
    }

    /// Vault: 300-700 mg sodium per hour of activity; at least about 500 mg/h when sweating heavily.
    static let lightSodiumPerHour = 300.0
    static let heavySodiumPerHour = 500.0...700.0
    /// Vault: 80-150 mg potassium per 500-750 mL in long or hot sessions.
    static let potassiumPerMl = (80.0 / 750)...(150.0 / 500)
    static let sodiumShareOfSalt = 0.38
    static let potassiumShareOfChloride = 0.524

    public static func plan(hours: Double, sweat: Sweat, bottleLitres: Double) throws -> Plan {
        guard hours.isFinite, hours > 0 else { throw ValidationError("Enter how long the activity is") }
        guard bottleLitres.isFinite, bottleLitres > 0 else { throw ValidationError("Enter how much water you carry") }
        let perHour = sweat == .heavy ? heavySodiumPerHour : lightSodiumPerHour...lightSodiumPerHour
        let sodium = (perHour.lowerBound * hours)...(perHour.upperBound * hours)
        let ml = bottleLitres * 1000
        let potassium = (potassiumPerMl.lowerBound * ml).rounded()...(potassiumPerMl.upperBound * ml).rounded()
        return Plan(sodiumMg: sodium,
                    saltGrams: (sodium.lowerBound / sodiumShareOfSalt / 1000)...(sodium.upperBound / sodiumShareOfSalt / 1000),
                    potassiumMg: potassium,
                    potassiumChlorideGrams: (potassium.lowerBound / potassiumShareOfChloride / 1000)...(potassium.upperBound / potassiumShareOfChloride / 1000),
                    sipMl: 180...360, sipEveryMinutes: 15...20)
    }
}
